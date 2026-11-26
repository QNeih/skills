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
# fixture_note <name> [frontmatter line...]: <vault>/wiki/projects/<name>.md
fixture_note() {
  local name=$1; shift
  mkdir -p "$VAULT/wiki/projects"
  { echo '---'; echo 'tags: [project]'; printf '%s\n' "$@"; echo '---'; } > "$VAULT/wiki/projects/$name.md"
}
# fixture_repo <path> [origin]: git repo with one commit
fixture_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main --template=
  git -C "$1" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m init
  [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
}

# --- Stand-in gh and project fixture (the GitHub boards) ---
# fixture_gh: a fake gh first on PATH. It appends each call's arguments (space-joined) to
# $GH_LOG and prints the canned answer whose key is the longest prefix of the call;
# no match prints nothing and succeeds. Needs fixture_new first. Sets GH_DIR, GH_LOG.
# A body passed as a file (--body-file <path>, --body-file=<path>, -F <path>, or - for stdin) is
# logged as its text in place of the path, so the log reads the same as for --body <text>.
# A call is one log line unless an argument holds a line break (a multi-line body): then it
# spans as many lines as the argument has.
fixture_gh() {
  export GH_DIR="$FIX/gh-canned" GH_LOG="$FIX/gh.log"
  mkdir -p "$FIX/bin" "$GH_DIR"; : > "$GH_LOG"
  cat > "$FIX/bin/gh" <<'GH'
#!/usr/bin/env bash
# body_text <value of a body-file flag>: the file's text (stdin for -); any other value unchanged,
# so gh api's -F key=value fields stay as they are
body_text() { if [ "$1" = - ]; then cat; elif [ -f "$1" ]; then cat "$1"; else printf '%s' "$1"; fi; }
args=() prev=""
for a in "$@"; do
  case $prev in --body-file|-F) args+=("$(body_text "$a")") ;;
  *) case $a in --body-file=*) args+=("--body-file=$(body_text "${a#*=}")") ;; *) args+=("$a") ;; esac ;;
  esac
  prev=$a
done
call="${args[*]}"
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
# gh_calls: the logged calls in order; a call takes one line, more when an argument has line breaks
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
# project's CLAUDE.md overrides the vault and projects root, and the run happens in a
# sandbox that blocks every write to a real location; a blocked write fails the test.

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

# --- Guard: the run cannot write to a real location ---
# The denied locations are the real vault, the real ~/.claude/skills and the whole real projects
# root; REAL_VAULT, REAL_HOME and REAL_PROJECTS_ROOT override them so the guard itself can be tested.
# The fixture under /tmp and Claude's own config stay writable.
# Limits:
# - A sandbox cannot start inside another sandbox (`sandbox_apply: Operation not permitted`), so the
#   harness breaks when Claude Code's own Bash sandbox is on.
# - A blocked write is reported only when its error reaches a tool result and names the full path:
#   a script that hides its error, or a write through a relative path, is blocked but not reported.
real_vault() {
  [ -n "${REAL_VAULT:-}" ] && { echo "$REAL_VAULT"; return; }
  grep -i vault "$HOME/.claude/CLAUDE.md" 2>/dev/null | grep -o '`/[^`]*`' | head -1 | tr -d '`'
}
# guard_start: sets GUARD_PROFILE (the sandbox-exec profile that denies writes to the real
# locations) and GUARD_NAMES (each location as given and as its real path, the two forms an error
# can name it by); fails when a location is missing
guard_start() {
  local home=${REAL_HOME:-$HOME} p real skills
  GUARD_NAMES=(); GUARD_PROFILE='(version 1)(allow default)'
  for p in "$(real_vault)" "$home/.claude/skills" "${REAL_PROJECTS_ROOT:-$HOME/Projects}"; do
    # the profile matches real paths, so symlinks are resolved
    real=$(cd "$p" 2>/dev/null && pwd -P) || { echo "guard: real location not found: '$p'; set REAL_VAULT, REAL_HOME or REAL_PROJECTS_ROOT" >&2; return 1; }
    GUARD_NAMES+=("$real"); [ "$p" = "$real" ] || GUARD_NAMES+=("$p")
    GUARD_PROFILE+="(deny file-write* (subpath $(guard_quote "$real")))"
    [ "$p" != "$home/.claude/skills" ] || skills=$real
  done
  # skills/synced/ is Claude Code's own skill-sync cache, rewritten on every start; a later rule wins
  GUARD_PROFILE+="(allow file-write* (subpath $(guard_quote "$skills/synced")))"
}
# guard_quote <path>: the path as a string of the sandbox profile language
guard_quote() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }
# guard_exec <command...>: runs the command, and every process it starts, inside the sandbox
guard_exec() { sandbox-exec -p "$GUARD_PROFILE" "$@"; }
# guard_check <record>: the record is the run's stream-json output. Fails when one of its tool
# results holds a blocked write ("Operation not permitted") to a denied location; prints each path
# under a denied location that such an error line names. A record it cannot read fails too.
guard_check() {
  local results denied
  results=$(jq -rR 'fromjson? | objects | "record-line", (.. | objects | select(.type == "tool_result") | .content
                    | if type == "string" then . else (.[]? | .text? // empty) end)' "$1") \
    || { echo "guard: cannot read the run's record '$1'"; return 1; }
  [ -n "$results" ] || { echo "guard: the run's record '$1' holds no JSON line, so its writes cannot be checked"; return 1; }
  # A path runs from the location's name to the end of the line, less what the common error shapes
  # put behind it: ": <reason>", a closing quote, " (Operation not permitted)", " for writing".
  denied=$(grep -i 'operation not permitted' <<<"$results" \
    | GUARD_ROOTS=$(printf '%s\n' "${GUARD_NAMES[@]}") awk '
        BEGIN { n = split(ENVIRON["GUARD_ROOTS"], roots, "\n") }
        { for (i = 1; i <= n; i++) for (rest = $0; (j = index(rest, roots[i])) > 0; rest = substr(rest, j + length(roots[i]))) {
            path = substr(rest, j)
            sub(/: .*/, "", path); sub(/[\047"]($|[ ,;)].*)/, "", path)
            sub(/ \([Oo]peration not permitted.*/, "", path); sub(/ for (writing|reading|appending).*/, "", path)
            print path } }' | sort -u)
  [ -z "$denied" ] || { echo "guard: the run tried to write to real locations (blocked):"; echo "$denied"; return 1; }
}
# claude_answer <record>: the run's final answer. A run that ended without one gives how it ended
# (the result's subtype and errors); a run that died before any result gives what it printed.
claude_answer() {
  local out
  out=$(jq -rR 'fromjson? | objects | select(.type == "result")
                | if (.result // "") != "" then .result
                  else "claude ended without an answer: \(.subtype // "no subtype")", (.errors[]? | tostring), (.error? // empty | tostring) end' "$1")
  [ -n "$out" ] || out=$(grep -v '^{' "$1")
  printf '%s\n' "$out"
}

# find_claude: prints the claude binary to run; with none, says so and fails. The one on PATH wins.
# A background session's shell has no ~/.local/bin on its PATH, so the installer's location is the fallback.
find_claude() {
  local fallback="$HOME/.local/bin/claude"
  command -v claude && return
  [ -x "$fallback" ] && { echo "$fallback"; return; }
  echo "claude is neither on PATH nor at $fallback: every live check would fail on empty output" >&2
  return 1
}

# run_claude <project dir> <prompt> [claude args...]: the final answer in CLAUDE_OUT, the whole run
# (stream-json, tool results included) in the file CLAUDE_RECORD; a guard hit fails the test.
# Call it directly, not in $(...), or the failure is lost.
# CLAUDE_MODEL picks the model, ALLOWED_TOOLS (comma-separated) scopes the tools.
run_claude() {
  local dir=$1 prompt=$2 claude; shift 2
  claude=$(find_claude) || exit 2
  command -v sandbox-exec >/dev/null || { echo "sandbox-exec is not on PATH (macOS only): without the sandbox the run could write to real files unseen" >&2; exit 2; }
  guard_start || exit 2
  # Claude Code's Bash tool loads the login profile, which puts e.g. Homebrew's real gh ahead of the
  # stand-ins; CLAUDE_ENV_FILE is sourced after it, so it puts the test's PATH in front of the profile's.
  # The profile skips ~/.zshrc, so an nvm-installed npm is missing there too: add nvm's newest node.
  local path=$PATH node_bin
  command -v npm >/dev/null || node_bin=$(ls -d "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
  [ -n "${node_bin:-}" ] && path=$path:$node_bin
  # A skill in the run may call claude itself: a claude found outside PATH gets its folder as the very
  # last entry, behind the profile's, so the stand-ins and the profile's order still win.
  local claude_dir last=
  claude_dir=$(dirname "$claude")
  case ":$PATH:" in *":$claude_dir:"*) ;; *) last=$(printf ':%q' "$claude_dir") ;; esac
  printf 'export PATH=%q:"$PATH"%s\n' "$path" "$last" > "$FIX/claude-env.sh"
  CLAUDE_RECORD="$FIX/claude-record.jsonl"
  # Hooks are off: the machine's own hooks act on real locations (a Stop hook syncs the real vault),
  # which the sandbox would block.
  (cd "$dir" && CLAUDE_ENV_FILE="$FIX/claude-env.sh" guard_exec "$claude" -p "$prompt" --permission-mode acceptEdits --add-dir "$FIX" \
    --settings '{"disableAllHooks":true}' \
    --allowedTools "${ALLOWED_TOOLS:-Skill,Read,Glob,Grep,Edit,Write,Bash(git *)}" \
    ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} --max-budget-usd "${CLAUDE_BUDGET:-1}" \
    --output-format stream-json --verbose \
    --no-session-persistence "$@" </dev/null) > "$CLAUDE_RECORD" 2>&1
  CLAUDE_OUT=$(claude_answer "$CLAUDE_RECORD")
  local g; g=$(guard_check "$CLAUDE_RECORD") || { fail "guard"; echo "$g"; }
}
# claude_said: every text the assistant printed during the last run_claude, not only the final answer
claude_said() {
  jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$CLAUDE_RECORD"
}
