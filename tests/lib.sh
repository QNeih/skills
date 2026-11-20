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

# --- Stand-in gh and project fixture (the GitHub boards) ---
# fixture_gh: a fake gh first on PATH. It appends each call's arguments (space-joined) as one
# line to $GH_LOG and prints the canned answer whose key is the longest prefix of the call;
# no match prints nothing and succeeds. Needs fixture_new first. Sets GH_DIR, GH_LOG.
fixture_gh() {
  export GH_DIR="$FIX/gh-canned" GH_LOG="$FIX/gh.log"
  mkdir -p "$FIX/bin" "$GH_DIR"; : > "$GH_LOG"
  cat > "$FIX/bin/gh" <<'GH'
#!/usr/bin/env bash
call="$*"
printf '%s\n' "$call" >> "$GH_LOG"
best=""
for k in "$GH_DIR"/*.key; do
  [ -f "$k" ] || continue
  key=$(cat "$k")
  if [ "$call" = "$key" ] || [[ "$call" == "$key "* ]]; then
    [ "${#key}" -gt "${#best}" ] && { best=$key; file="${k%.key}.json"; }
  fi
done
if [ -n "$best" ]; then
  # a gh_seq answer: the n-th matching call prints the n-th line (the last line repeats)
  if [ -f "${file%.json}.seq" ]; then
    c="${file%.json}.count"; n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
    total=$(wc -l < "${file%.json}.seq" | tr -d ' ')
    [ "$n" -le "$total" ] || n=$total
    sed -n "${n}p" "${file%.json}.seq"
  else
    cat "$file"
  fi
fi
exit 0
GH
  chmod +x "$FIX/bin/gh"
  export PATH="$FIX/bin:$PATH"
}
# gh_can <call prefix> <json>: canned answer for calls starting with the prefix
gh_can() {
  local n; n=$(find "$GH_DIR" -name '*.key' | wc -l | tr -d ' ')
  printf '%s' "$1" > "$GH_DIR/$n.key"; printf '%s\n' "$2" > "$GH_DIR/$n.json"
}
# gh_seq <call prefix> <answer>...: answers the matching calls one after the other, one argument each
gh_seq() {
  local n; n=$(find "$GH_DIR" -name '*.key' | wc -l | tr -d ' ')
  printf '%s' "$1" > "$GH_DIR/$n.key"; : > "$GH_DIR/$n.json"; shift
  printf '%s\n' "$@" > "$GH_DIR/$n.seq"
}
# gh_calls: the logged calls, one per line
gh_calls() { cat "$GH_LOG"; }

# fixture_settings <checkout> [settings line...]: <checkout>/.claude/project.md with the lines
# as front matter, committed when <checkout> is a git repo
fixture_settings() {
  local dir=$1; shift
  mkdir -p "$dir/.claude"
  { echo '---'; [ $# -eq 0 ] || printf '%s\n' "$@"; echo '---'; } > "$dir/.claude/project.md"
  [ ! -e "$dir/.git" ] || {
    git -C "$dir" add .claude/project.md
    git -C "$dir" -c user.name=t -c user.email=t@acme.test commit -q -m "Board settings"
  }
}
# fixture_project <name> [settings line...]: nested layout, the checkout at
# $PROJECTS_ROOT/<name>/<name> with its settings file
fixture_project() {
  local name=$1; shift
  fixture_repo "$PROJECTS_ROOT/$name/$name"
  fixture_settings "$PROJECTS_ROOT/$name/$name" "$@"
}
# fixture_project_flat <name> [settings line...]: flat layout, the checkout at
# $PROJECTS_ROOT/<name> with its settings file
fixture_project_flat() {
  local name=$1; shift
  fixture_repo "$PROJECTS_ROOT/$name"
  fixture_settings "$PROJECTS_ROOT/$name" "$@"
}
# fixture_worktree <checkout> <ticket>: ticket worktree of the checkout on feature/<ticket>
fixture_worktree() {
  git -C "$1" worktree add -q "$1/.claude/worktrees/$2" -b "feature/$2"
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
               # flat and nested checkouts
               find "$root"/*/.scratch "$root"/*/.handoffs "$root"/*/*/.scratch "$root"/*/*/.handoffs -newer "$GUARD_MARK" | grep -v "^$root/skills/"
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
