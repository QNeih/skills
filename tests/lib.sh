# Shared test helpers. Source it: . "$(dirname "$0")/lib.sh"
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")
FAILS=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
# expect <name> <haystack> <line>: haystack has the exact line
expect() { grep -qxF -- "$3" <<<"$2" && pass "$1" || { fail "$1"; printf '     want: %s\n     got:\n%s\n' "$3" "$(sed 's/^/       /' <<<"$2")"; }; }
done_testing() { [ "$FAILS" -eq 0 ]; }

# --- Fixture builder: a throwaway vault and projects root under /tmp ---
# fixture_new: sets FIX, VAULT, PROJECTS_ROOT (exported, real paths)
fixture_new() {
  FIX=$(cd "$(mktemp -d /tmp/skills-test.XXXXXX)" && pwd -P)
  export VAULT="$FIX/vault" PROJECTS_ROOT="$FIX/projects"
  mkdir -p "$VAULT/Projects" "$PROJECTS_ROOT"
  trap 'rm -rf "$FIX"' EXIT
}
# fixture_note <name> [frontmatter line...]: <vault>/Projects/<name>/<name>.md
fixture_note() {
  local name=$1; shift
  mkdir -p "$VAULT/Projects/$name"
  { echo '---'; echo 'tags: [project]'; printf '%s\n' "$@"; echo '---'; } > "$VAULT/Projects/$name/$name.md"
}
# fixture_repo <path> [origin]: git repo with one commit
fixture_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main --template=
  git -C "$1" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m init
  [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
}

# --- claude -p harness (live tests) ---
# Runs use Quinn's real config (a temp CLAUDE_CONFIG_DIR is not logged in), so:
# skills are installed as t-<name> (personal skills win name clashes), the fixture
# project's CLAUDE.md overrides the vault and projects root, and a guard fails the
# test if anything real changed during the run.

# fixture_claude_md <project dir>
fixture_claude_md() {
  cat > "$1/CLAUDE.md" <<MD
# Test fixture

For this run the vault is \`$VAULT\` and the projects root is \`$PROJECTS_ROOT\`.
They replace any other vault or projects root path, including the ones in ~/.claude/CLAUDE.md.
Run scripts with \`VAULT=$VAULT PROJECTS_ROOT=$PROJECTS_ROOT\`. Never read or write outside \`$FIX\`.
MD
}

# install_skill <skill dir> <name> <project dir>: copy as .claude/skills/t-<name>
install_skill() {
  local t="$3/.claude/skills/t-$2"
  mkdir -p "$t" && cp -R "$1"/. "$t"/
  awk -v n="t-$2" 'NR > 1 && /^---$/ { fm = 1 } !fm && /^name:/ { $0 = "name: " n } { print }' "$1/SKILL.md" > "$t/SKILL.md"
}

# Real locations the guard watches; overridable so the guard itself can be tested.
real_vault() {
  [ -n "${REAL_VAULT:-}" ] && { echo "$REAL_VAULT"; return; }
  grep -i vault "$HOME/.claude/CLAUDE.md" 2>/dev/null | grep -o '`/[^`]*`' | head -1 | tr -d '`'
}
guard_start() { GUARD_MARK=$(mktemp /tmp/skills-guard.XXXXXX); }
# guard_check: lists real files changed since guard_start; fails if any
guard_check() {
  local home=${REAL_HOME:-$HOME} root=${REAL_PROJECTS_ROOT:-$HOME/Projects} vault changed
  vault=$(real_vault)
  [ -d "$vault" ] || { echo "guard: real vault not found; set REAL_VAULT"; return 1; }
  changed=$( { find "$vault" -newer "$GUARD_MARK"
               # skills/synced/ is Claude Code's own skill-sync cache, rewritten on every start
               find -L "$home/.claude/skills" "$home/.claude/briefing" -newer "$GUARD_MARK" | grep -v "^$home/.claude/skills/synced/"
               find "$root"/*/.scratch "$root"/*/.handoffs -newer "$GUARD_MARK" | grep -v "^$root/skills/"
             } 2>/dev/null)
  rm -f "$GUARD_MARK"
  [ -z "$changed" ] || { echo "guard: real files changed during the run:"; echo "$changed"; return 1; }
}

# run_claude <project dir> <prompt> [claude args...]: output in CLAUDE_OUT; a guard hit fails the test.
# Call it directly, not in $(...), or the failure is lost.
# CLAUDE_MODEL picks the model, ALLOWED_TOOLS (comma-separated) scopes the tools.
run_claude() {
  local dir=$1 prompt=$2; shift 2
  guard_start
  CLAUDE_OUT=$(cd "$dir" && claude -p "$prompt" --permission-mode acceptEdits --add-dir "$FIX" \
    --allowedTools "${ALLOWED_TOOLS:-Skill,Read,Glob,Grep,Edit,Write,Bash(git *)}" \
    ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} --max-budget-usd "${CLAUDE_BUDGET:-1}" \
    --no-session-persistence "$@" </dev/null 2>&1)
  local g; g=$(guard_check) || { fail "guard"; echo "$g"; }
}
