#!/usr/bin/env bash
# /send through claude -p, against a local bare remote: close without a reason asks, with one closes; pushed commits still sent; lint commit, push
# and the "PR on <host> not supported" stop; a ticket worktree is removed, port change and all; without git: card to Done, ticket files deleted.
. "$(dirname "$0")/lib.sh"
fixture_new
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Edit,Write,Bash(git *),Bash(bash *),Bash(VAULT=*),Bash(npm *),Bash(rm *),Bash(rmdir *),Bash(ls *),Bash(find *),Bash(cd *),Bash(claude agents *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}

setup() { fixture_claude_md "$1"; install_skill "$REPO_DIR/skills/send" send "$1"; }
# run_send <dir>: CLAUDE_OUT = every text the assistant printed
run_send() {
  run_claude "$1" "/t-send${2:+ $2}" --output-format stream-json --verbose
  CLAUDE_OUT=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' <<<"$CLAUDE_OUT")
}
column() { awk -v h="$2" '/^## / { on = tolower($0) ~ h; next } /^%% kanban/ { on = 0 } on && NF' "$1"; }
# ticket <dir> <id> <slug> <branch> [base]: .scratch ticket.md and handoff, as /work writes them
ticket() {
  mkdir -p "$1/.scratch/$2-$3" "$1/.handoffs"
  { echo "# $2: Card $2"; echo; echo "ref: $2"; echo "branch: $4"; [ -z "${5:-}" ] || echo "base: $5"
    echo "board: $board"; echo "Status: ready-for-agent"; } > "$1/.scratch/$2-$3/ticket.md"
  echo "handoff $2" > "$1/.handoffs/HANDOFF-$2.md"
}

# --- git project with a local bare remote ---
fixture_note Acme
board="$VAULT/Projects/Acme/Acme Board.md"
printf -- '## To do\n\n## In progress\n\n- [ ] **ACM-1 · Old work**\n\tBranch `feature/ACM-1`\n- [ ] **ACM-2 · Login fails** #bug\n\tBranch `bugfix/ACM-2`\n- [ ] **ACM-4 · Worktree ticket**\n\tBranch `feature/ACM-4`\n\n## Done\n\n**Complete**\n' > "$board"
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
echo '{ "version": "0.0.1", "configurations": [{ "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["start", "--", "--port", "5173"], "port": 5173 }] }' > "$acme/.claude/launch.json"
sed -i.bak 's/^var /let /' "$acme/src/a.js" && rm "$acme/src/a.js.bak"
git -C "$acme" add -A && git -C "$acme" commit -qm "Add app" && git -C "$acme" push -q -u origin main 2>/dev/null

# Close: branch pushed, nothing on it. Without a reason it asks and changes nothing
git -C "$acme" checkout -q -b feature/ACM-1 && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-1 old-work feature/ACM-1 main
run_send "$acme"
grep -qF 'ACM-1 · Old work' <<<"$(column "$board" 'in progress')" && [ -f "$acme/.scratch/ACM-1-old-work/ticket.md" ] \
  && git -C "$remote" rev-parse -q --verify feature/ACM-1 >/dev/null \
  && pass "close without reason: nothing changed" || { fail "close without reason: nothing changed"; echo "$CLAUDE_OUT" | tail -20; }

# With a reason: card to Done with the reason, branch gone locally and on origin, ticket files gone
run_send "$acme" "already fixed by ACM-0"
grep -qF $'- [x] **ACM-1 · Old work**\n\tBranch `feature/ACM-1`\n\tClosed without code: already fixed by ACM-0' <<<"$(column "$board" 'done')" \
  && pass "close: card ticked in Done with the reason" || { fail "close: card ticked in Done with the reason"; cat "$board"; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(git -C "$acme" branch --list feature/ACM-1)" ] && ! git -C "$remote" rev-parse -q --verify feature/ACM-1 >/dev/null \
  && pass "close: branch deleted locally and on origin" || fail "close: branch deleted locally and on origin"
[ ! -e "$acme/.scratch/ACM-1-old-work" ] && [ ! -e "$acme/.handoffs/HANDOFF-ACM-1.md" ] \
  && pass "close: ticket files deleted" || fail "close: ticket files deleted"
[ "$(git -C "$acme" rev-parse HEAD)" = "$(git -C "$acme" rev-parse origin/main)" ] \
  && pass "close: no commit, back on main" || fail "close: no commit, back on main"

# Committed and pushed, no PR yet: send goes on past preflight instead of saying nothing to send
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b feature/ACM-3
echo 'let d = 4' > "$acme/src/d.js"
git -C "$acme" add src/d.js && git -C "$acme" commit -qm "Add d" && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-3 pushed-work feature/ACM-3 main
run_send "$acme"
! grep -qi 'nothing to send' <<<"$CLAUDE_OUT" && grep -qE 'PR on .+ not supported' <<<"$CLAUDE_OUT" \
  && pass "pushed commits: reach the PR step" || { fail "pushed commits: reach the PR step"; echo "$CLAUDE_OUT" | tail -20; }

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

# Ticket worktree no background session was started in, with a dev server's port moved: the port change is dropped, the worktree removed
wt="$acme/.claude/worktrees/ACM-4"
git -C "$acme" worktree add -q "$wt" -b feature/ACM-4 origin/main && git -C "$wt" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-4 worktree-ticket feature/ACM-4 main
sed -i.bak 's/5173/5174/g' "$wt/.claude/launch.json" && rm "$wt/.claude/launch.json.bak"
run_send "$wt" "superseded by ACM-0"
[ ! -e "$wt" ] && ! git -C "$acme" worktree list | grep -qF "$wt" \
  && pass "worktree: removed with its port change" || { fail "worktree: removed with its port change"; git -C "$wt" status --short; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(git -C "$acme" branch --list feature/ACM-4)" ] && ! git -C "$remote" rev-parse -q --verify feature/ACM-4 >/dev/null \
  && pass "worktree: branch deleted locally and on origin" || fail "worktree: branch deleted locally and on origin"
grep -qF -- '- [x] **ACM-4 · Worktree ticket**' <<<"$(column "$board" 'done')" && [ ! -e "$acme/.scratch/ACM-4-worktree-ticket" ] \
  && pass "worktree: card in Done, ticket files deleted" || { fail "worktree: card in Done, ticket files deleted"; cat "$board"; }

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
