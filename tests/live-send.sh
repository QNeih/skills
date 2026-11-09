#!/usr/bin/env bash
# /send through claude -p, against a local bare remote: nothing to send; lint commit, push
# and the "PR on <host> not supported" stop; without git: card to Done, ticket files deleted.
. "$(dirname "$0")/lib.sh"
fixture_new
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Edit,Write,Bash(git *),Bash(bash *),Bash(VAULT=*),Bash(npm *),Bash(rm *),Bash(rmdir *),Bash(ls *),Bash(find *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}

setup() { fixture_claude_md "$1"; install_skill "$REPO_DIR/skills/send" send "$1"; }
# run_send <dir>: CLAUDE_OUT = every text the assistant printed
run_send() {
  run_claude "$1" "/t-send" --output-format stream-json --verbose
  CLAUDE_OUT=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' <<<"$CLAUDE_OUT")
}
column() { awk -v h="$2" '/^## / { on = tolower($0) ~ h; next } /^%% kanban/ { on = 0 } on && NF' "$1"; }
# ticket <dir> <id> <slug> <branch> [base]: .scratch ticket.md and handoff, as /ticket writes them
ticket() {
  mkdir -p "$1/.scratch/$2-$3" "$1/.handoffs"
  { echo "# $2: Card $2"; echo; echo "ref: $2"; echo "branch: $4"; [ -z "${5:-}" ] || echo "base: $5"
    echo "board: $board"; echo "Status: ready-for-agent"; } > "$1/.scratch/$2-$3/ticket.md"
  echo "handoff $2" > "$1/.handoffs/HANDOFF-$2.md"
}

# --- git project with a local bare remote ---
fixture_note Acme
board="$VAULT/Projects/Acme/Acme Board.md"
printf -- '## To do\n\n## In progress\n\n- [ ] **ACM-1 · Old work**\n\tBranch `feature/ACM-1`\n- [ ] **ACM-2 · Login fails** #bug\n\tBranch `bugfix/ACM-2`\n\n## Done\n\n**Complete**\n' > "$board"
acme="$PROJECTS_ROOT/acme" remote="$FIX/acme.git"
git init -q --bare -b main "$remote"
fixture_repo "$acme" "$remote"
git -C "$acme" config user.name t; git -C "$acme" config user.email t@acme.test
setup "$acme"
mkdir -p "$acme/src"
echo 'var a = 1' > "$acme/src/a.js"
cat > "$acme/package.json" <<'JSON'
{ "name": "acme", "scripts": { "lint-fix": "sed -i.bak 's/^var /let /' src/*.js && rm src/*.bak" } }
JSON
sed -i.bak 's/^var /let /' "$acme/src/a.js" && rm "$acme/src/a.js.bak"
git -C "$acme" add -A && git -C "$acme" commit -qm "Add app" && git -C "$acme" push -q -u origin main 2>/dev/null

# Nothing to send: branch pushed, tree clean apart from its ticket files
git -C "$acme" checkout -q -b feature/ACM-1 && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-1 old-work feature/ACM-1 main
run_send "$acme"
grep -qi 'nothing to send' <<<"$CLAUDE_OUT" && pass "nothing to send: says so" || { fail "nothing to send: says so"; echo "$CLAUDE_OUT" | tail -20; }
[ "$(git -C "$acme" rev-parse HEAD)" = "$(git -C "$acme" rev-parse origin/main)" ] \
  && pass "nothing to send: no commit" || fail "nothing to send: no commit"
grep -qF 'ACM-1 · Old work' <<<"$(column "$board" 'in progress')" && pass "nothing to send: card stays" || fail "nothing to send: card stays"

# Committed-but-unpushed work plus an uncommitted file; lint must cover both
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b bugfix/ACM-2 && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-2 login-fails bugfix/ACM-2 main
echo 'var b = 2' > "$acme/src/b.js"
git -C "$acme" add src/b.js && git -C "$acme" commit -qm "Add b"
echo 'var c = 3' > "$acme/src/c.js"
run_send "$acme"

grep -qE 'PR on .+ not supported' <<<"$CLAUDE_OUT" && pass "non-GitHub origin: PR on <host> not supported" \
  || { fail "non-GitHub origin: PR on <host> not supported"; echo "$CLAUDE_OUT" | tail -20; }
pushed=$(git -C "$remote" rev-parse bugfix/ACM-2 2>/dev/null)
[ -n "$pushed" ] && [ "$pushed" = "$(git -C "$acme" rev-parse HEAD)" ] && pass "push: remote has HEAD" || fail "push: remote has HEAD"
[ "$(git -C "$remote" show bugfix/ACM-2:src/b.js 2>/dev/null)$(git -C "$remote" show bugfix/ACM-2:src/c.js 2>/dev/null)" = "let b = 2let c = 3" ] \
  && pass "lint: committed and uncommitted paths fixed" || fail "lint: committed and uncommitted paths fixed"
# The lint commit changes only var → let lines, in both files
lint=
for c in $(git -C "$remote" rev-list main..bugfix/ACM-2); do
  d=$(git -C "$remote" show --format= -U0 "$c" | grep -E '^[-+][^-+]')
  [ -n "$d" ] && ! grep -qvE '^[-+](var|let) [bc] = [23]$' <<<"$d" && [ "$(grep -c '^+let' <<<"$d")" = 2 ] && lint=$c
done
[ -n "$lint" ] && pass "lint: own commit" || { fail "lint: own commit"; git -C "$remote" log -p main..bugfix/ACM-2; }
[ -z "$(git -C "$acme" status --porcelain | grep -vE '\.(scratch|handoffs)/')" ] && pass "commit: tree clean" || fail "commit: tree clean"
grep -qF 'ACM-2 · Login fails' <<<"$(column "$board" 'in progress')" && pass "stop: card not moved" || { fail "stop: card not moved"; cat "$board"; }
[ "$(git -C "$acme" branch --show-current)" = bugfix/ACM-2 ] && [ -f "$acme/.scratch/ACM-2-login-fails/ticket.md" ] \
  && pass "stop: no cleanup" || fail "stop: no cleanup"

# --- project without git: two tickets, the one in progress on the board is sent ---
fixture_note Beta
board="$VAULT/Projects/Beta/Beta Board.md"
printf -- '## To do\n\n- [ ] **BET-9 · Later**\n\n## In progress\n\n- [ ] **BET-3 · Write the intro**\n\tTwo paragraphs.\n\n## Done\n\n**Complete**\n- [x] **BET-1 · Setup**\n\n\n%%%% kanban:settings\n%%%%\n' > "$board"
beta="$PROJECTS_ROOT/beta"
mkdir -p "$beta"
setup "$beta"
ticket "$beta" BET-3 write-intro none
ticket "$beta" BET-9 later none
run_send "$beta"

[ "$(column "$board" 'done')" = $'**Complete**\n- [x] **BET-1 · Setup**\n- [x] **BET-3 · Write the intro**\n\tTwo paragraphs.' ] \
  && pass "no git: card ticked at the end of Done" || { fail "no git: card ticked at the end of Done"; cat "$board"; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(column "$board" 'in progress')" ] && pass "no git: card left In progress" || fail "no git: card left In progress"
[ ! -e "$beta/.scratch/BET-3-write-intro" ] && [ ! -e "$beta/.handoffs/HANDOFF-BET-3.md" ] \
  && pass "no git: ticket files deleted" || fail "no git: ticket files deleted"
[ -f "$beta/.scratch/BET-9-later/ticket.md" ] && [ -f "$beta/.handoffs/HANDOFF-BET-9.md" ] \
  && pass "no git: other ticket's files stay" || fail "no git: other ticket's files stay"
[ ! -e "$beta/.git" ] && pass "no git: no repo created" || fail "no git: no repo created"
done_testing
