#!/usr/bin/env bash
# /work on a vault board, through claude -p: picks the card, claims it, cuts the branch,
# writes ticket.md and the handoff in the main checkout, prints the route.
. "$(dirname "$0")/lib.sh"
fixture_new
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Edit,Write,Bash(git *),Bash(bash *),Bash(VAULT=*),Bash(mkdir *),Bash(ls *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}

# setup <project dir>: fixture CLAUDE.md that stops after the route, skill installed as t-work
setup() {
  fixture_claude_md "$1"
  echo 'This is a test run: stop right after /t-work prints its `Route:` line, without starting the route.' >> "$1/CLAUDE.md"
  install_skill "$REPO_DIR/skills/work" work "$1"
}
# run_ticket <dir> <prompt>: CLAUDE_OUT = every text the assistant printed, not only the last one
run_ticket() {
  run_claude "$1" "$2" --output-format stream-json --verbose
  CLAUDE_OUT=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' <<<"$CLAUDE_OUT")
}
# column <board file> <heading regex>: non-empty lines of that column
column() { awk -v h="$2" '/^## / { on = tolower($0) ~ h; next } /^%% kanban/ { on = 0 } on && NF' "$1"; }

# --- git project, run from a linked worktree, no argument ---
fixture_note Acme
board="$VAULT/Projects/Acme/Acme Board.md"
cat > "$board" <<'MD'
---

kanban-plugin: board

---

## To do

- [ ] **ACM-3 · Export as PDF** #urgent
	Needs: ACM-1
- [ ] **ACM-1 · Add export button**
	Export the list as CSV.
- [ ] **ACM-2 · Login fails on Safari** #bug #urgent
	The login button does nothing on Safari 18.
	Braucht: ACM-4


## In Progress

- [ ] **ACM-5 · Older card**


## Done

**Complete**
- [x] **ACM-4 · Setup**
MD
acme="$PROJECTS_ROOT/acme"
fixture_repo "$acme"
git -C "$acme" checkout -q -b develop
git -C "$acme" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m "develop work"
git -C "$acme" checkout -q main
wt="$FIX/acme-wt"
git -C "$acme" worktree add -q -b wt "$wt" main
setup "$wt"

run_ticket "$wt" "/t-work"

# first ranked row, not the first key anywhere ("ACM-3 is blocked by ACM-1" may come before the list)
[ "$(grep -E '^[[:space:]]*([0-9]+[.)]|[-*]) .*ACM-[123]' <<<"$CLAUDE_OUT" | grep -oE 'ACM-[123]' | head -1)" = ACM-2 ] && grep -q 'ACM-1' <<<"$CLAUDE_OUT" \
  && pass "pick: list printed, urgent unblocked card first" || { fail "pick: list printed, urgent unblocked card first"; echo "$CLAUDE_OUT"; }
grep -qE '^Route: /' <<<"$CLAUDE_OUT" && pass "route line printed" || { fail "route line printed"; echo "$CLAUDE_OUT" | tail -20; }
want=$'- [ ] **ACM-5 · Older card**\n- [ ] **ACM-2 · Login fails on Safari** #bug #urgent\n\tThe login button does nothing on Safari 18.\n\tBraucht: ACM-4\n\tBranch `bugfix/ACM-2`'
[ "$(column "$board" 'in progress')" = "$want" ] && pass "claim: card at the end of In progress, branch noted" \
  || { fail "claim: card at the end of In progress, branch noted"; cat "$board"; }
[ "$(column "$board" 'to do')" = $'- [ ] **ACM-3 · Export as PDF** #urgent\n\tNeeds: ACM-1\n- [ ] **ACM-1 · Add export button**\n\tExport the list as CSV.' ] \
  && pass "claim: card left To do" || fail "claim: card left To do"
git -C "$acme" merge-base --is-ancestor develop bugfix/ACM-2 2>/dev/null \
  && pass "branch: bugfix/ACM-2 from develop" || fail "branch: bugfix/ACM-2 from develop"
t=$(ls "$acme"/.scratch/ACM-2-*/ticket.md 2>/dev/null | head -1)
[ -n "$t" ] && pass "ticket.md in the main checkout" || fail "ticket.md in the main checkout"
expect "ticket.md: branch" "$(cat "$t" 2>/dev/null)" "branch: bugfix/ACM-2"
expect "ticket.md: ref" "$(cat "$t" 2>/dev/null)" "ref: ACM-2"
[ ! -e "$wt/.scratch" ] && pass "nothing in the worktree's .scratch" || fail "nothing in the worktree's .scratch"
grep -qF "$t" "$acme/.handoffs/HANDOFF-ACM-2.md" 2>/dev/null \
  && pass "handoff points at ticket.md by absolute path" || fail "handoff points at ticket.md by absolute path"

# --- project without git, digits only ---
fixture_note Beta
board="$VAULT/Projects/Beta/Beta Board.md"
printf -- '## To do\n\n- [ ] **BET-2 · Other card**\n- [ ] **BET-3 · Write the intro**\n\tTwo paragraphs for the landing page.\n\n## In progress\n\n## Done\n' > "$board"
beta="$PROJECTS_ROOT/beta"
mkdir -p "$beta"
setup "$beta"

run_ticket "$beta" "/t-work 3"

grep -qE '^Route: /' <<<"$CLAUDE_OUT" && pass "no git: route line printed" || { fail "no git: route line printed"; echo "$CLAUDE_OUT" | tail -20; }
[ "$(column "$board" 'in progress')" = $'- [ ] **BET-3 · Write the intro**\n\tTwo paragraphs for the landing page.' ] \
  && pass "no git: card in In progress, no branch line" || { fail "no git: card in In progress, no branch line"; cat "$board"; }
t=$(ls "$beta"/.scratch/BET-3-*/ticket.md 2>/dev/null | head -1)
expect "no git: ticket.md in the project folder with ref" "$(cat "$t" 2>/dev/null)" "ref: BET-3"
grep -qE '^branch: .*/' "$t" 2>/dev/null && fail "no git: no branch in ticket.md" || pass "no git: no branch in ticket.md"
[ -f "$beta/.handoffs/HANDOFF-BET-3.md" ] && pass "no git: handoff" || fail "no git: handoff"
[ ! -e "$beta/.git" ] && pass "no git: no repo created" || fail "no git: no repo created"
done_testing
