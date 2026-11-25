#!/usr/bin/env bash
# work/prune-worktrees.sh: which worktrees of a fixture checkout it removes, with their local
# branches, and which it lists and leaves alone. Stand-ins: gh (merged PRs), claude (sessions)
# and tickets.sh (ticket state), so no real worktree, board or session is read or changed.
. "$(dirname "$0")/lib.sh"
fixture_new; fixture_gh

# The script under test runs from a copy, next to the real project.sh and a stand-in tickets.sh
# that prints the state file of the ticket and logs the call.
mkdir -p "$FIX/sk" "$FIX/tickets"
cp "$REPO_DIR/skills/work/prune-worktrees.sh" "$REPO_DIR/skills/work/project.sh" "$FIX/sk/"
export TICKETS_DIR="$FIX/tickets" TICKETS_LOG="$FIX/tickets.log"; : > "$TICKETS_LOG"
cat > "$FIX/sk/tickets.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$TICKETS_LOG"
[ "$1" = show ] && [ -f "$TICKETS_DIR/$2" ] && printf '{"state":"%s"}\n' "$(cat "$TICKETS_DIR/$2")"
SH
# Stand-in claude: `agents` prints $CLAUDE_AGENTS, or fails when $CLAUDE_FAIL is set; logs each call
export CLAUDE_AGENTS="$FIX/agents.json" CLAUDE_LOG="$FIX/claude.log"; echo '[]' > "$CLAUDE_AGENTS"; : > "$CLAUDE_LOG"
cat > "$FIX/bin/claude" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
[ -z "${CLAUDE_FAIL:-}" ] || { echo "no sessions" >&2; exit 1; }
cat "$CLAUDE_AGENTS"
SH
chmod +x "$FIX/bin/claude"
prune() { bash "$FIX/sk/prune-worktrees.sh" "$@"; }
g() { git -c user.name=t -c user.email=t@acme.test "$@"; }

# new_checkout <name> [settings line...]: project with an origin holding main and a .gitignore
new_checkout() {
  local name=$1; shift
  fixture_project_flat "$name" "$@"
  local c="$PROJECTS_ROOT/$name"
  printf '.scratch/\n.handoffs/\n' > "$c/.gitignore"
  g -C "$c" add .gitignore; g -C "$c" commit -q -m ignore
  git init -q --bare --template= "$FIX/$name-origin.git"
  git -C "$c" remote add origin "$FIX/$name-origin.git"
  git -C "$c" push -q -u origin main
}
# wt <checkout> <name> <branch | --detach>: linked worktree at .claude/worktrees/<name>
wt() {
  if [ "$3" = --detach ]; then git -C "$1" worktree add -q --detach "$1/.claude/worktrees/$2"
  else git -C "$1" worktree add -q "$1/.claude/worktrees/$2" -b "$3"; fi
}
# commit <worktree>: one commit of its own (the message makes its hash unique); push <worktree>: its branch to origin
commit() { echo x > "$1/work.txt"; g -C "$1" add work.txt; g -C "$1" commit -q -m "work in $1"; }
push() { git -C "$1" push -q origin HEAD; }
has_branch() { git -C "$c" rev-parse -q --verify "refs/heads/$1" >/dev/null; }

new_checkout acme 'board: github' 'project: 4' 'key: ACM' 'repo: QuinnNei/acme'
c="$PROJECTS_ROOT/acme"; w="$c/.claude/worktrees"
wt "$c" ACM-1 feature/ACM-1; commit "$w/ACM-1"; push "$w/ACM-1"          # (a) on origin
wt "$c" ACM-2 feature/ACM-2; commit "$w/ACM-2"                            # (b) merged PR
gh_can 'pr list --head feature/ACM-2 --state merged' '[{"number":7}]'
gh_can 'pr list --head' '[]'
wt "$c" ACM-3 bugfix/ACM-3; commit "$w/ACM-3"; echo CLOSED > "$TICKETS_DIR/ACM-3"   # (c) ticket closed
wt "$c" ACM-4 feature/ACM-4; commit "$w/ACM-4"; echo OPEN > "$TICKETS_DIR/ACM-4"    # none of them
wt "$c" ACM-5 feature/ACM-5; push "$w/ACM-5"; echo changed >> "$w/ACM-5/.gitignore" # modified tracked file
wt "$c" ACM-6 feature/ACM-6; push "$w/ACM-6"; echo new > "$w/ACM-6/notes.txt"       # untracked file
wt "$c" ACM-7 feature/ACM-7; push "$w/ACM-7"                                         # ignored ticket files only
mkdir -p "$w/ACM-7/.scratch/ACM-7-x" "$w/ACM-7/.handoffs"; echo t > "$w/ACM-7/.scratch/ACM-7-x/ticket.md"; echo h > "$w/ACM-7/.handoffs/HANDOFF-ACM-7.md"
wt "$c" ACM-8 feature/ACM-8; push "$w/ACM-8"; git -C "$c" worktree lock "$w/ACM-8"   # locked
wt "$c" ACM-9 feature/ACM-9; push "$w/ACM-9"                                         # a session's worktree
wt "$c" ACM-90 feature/ACM-90                                                        # shares the session's name prefix
wt "$c" agent-a1 worktree-agent-a1                                                   # non-ticket, nothing of its own
wt "$c" agent-a2 worktree-agent-a2; commit "$w/agent-a2"                             # non-ticket, own commit
wt "$c" det-1 --detach                                                               # detached, on origin
wt "$c" ACM-11 --detach; commit "$w/ACM-11"; echo CLOSED > "$TICKETS_DIR/ACM-11"     # detached, own commit
wt "$c" other feature/other; commit "$w/other"; echo CLOSED > "$TICKETS_DIR/other"   # no ticket branch
printf '[{"id":"s9","cwd":"%s","kind":"background","state":"done"},{"id":"s0","cwd":"%s","kind":"background","state":"blocked"}]\n' "$w/ACM-9" "$c" > "$CLAUDE_AGENTS"
cd "$c" || exit 1

want="removed: $w/ACM-1
removed: $w/ACM-2
removed: $w/ACM-3
kept: $w/ACM-4 — not finished
kept: $w/ACM-5 — uncommitted changes
kept: $w/ACM-6 — uncommitted changes
removed: $w/ACM-7
kept: $w/ACM-8 — locked
claude rm s9 — $w/ACM-9
removed: $w/ACM-90
removed: $w/agent-a1
kept: $w/agent-a2 — not finished
removed: $w/det-1
kept: $w/ACM-11 — not finished
kept: $w/other — not finished"
same_lines() { [ "$(sort <<<"$1")" = "$(sort <<<"$2")" ]; }
state() { git worktree list --porcelain; git branch; }

# --dry-run: the lines of a real run, nothing removed
before=$(state)
out=$(prune --dry-run); rc=$?
[ $rc -eq 0 ] && pass "dry run: exit 0" || fail "dry run: exit 0, got $rc"
same_lines "$out" "$want" && pass "dry run: one line per linked worktree" || { fail "dry run: one line per linked worktree"; echo "$out"; }
[ "$before" = "$(state)" ] && pass "dry run: worktrees and branches unchanged" || fail "dry run: worktrees and branches unchanged"

out=$(prune); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0, got $rc"
same_lines "$out" "$want" && pass "one line per linked worktree, none for the main checkout" || { fail "one line per linked worktree, none for the main checkout"; echo "$out"; }
for n in ACM-1 ACM-2 ACM-3 ACM-7 ACM-90 agent-a1 det-1; do
  [ ! -e "$w/$n" ] && pass "$n: worktree removed" || fail "$n: worktree removed"
done
for b in feature/ACM-1 feature/ACM-2 bugfix/ACM-3 feature/ACM-7 feature/ACM-90 worktree-agent-a1; do
  ! has_branch "$b" && pass "$b: local branch deleted" || fail "$b: local branch deleted"
done
for n in ACM-4 ACM-5 ACM-6 ACM-8 ACM-9 agent-a2 ACM-11 other; do
  [ -d "$w/$n" ] && pass "$n: worktree kept" || fail "$n: worktree kept"
done
for b in feature/ACM-4 feature/ACM-5 feature/ACM-6 feature/ACM-8 feature/ACM-9 worktree-agent-a2 feature/other main; do
  has_branch "$b" && pass "$b: local branch kept" || fail "$b: local branch kept"
done
[ -f "$w/ACM-6/notes.txt" ] && grep -q changed "$w/ACM-5/.gitignore" && pass "uncommitted work untouched" || fail "uncommitted work untouched"
expect "sessions read for the main checkout" "$(cat "$CLAUDE_LOG")" "agents --json --all --cwd $c"
expect "merged PR looked up by branch" "$(gh_calls)" "pr list --head feature/ACM-2 --state merged --json number"
expect "ticket state read through tickets.sh" "$(cat "$TICKETS_LOG")" "show ACM-4"
! grep -q 'ACM-11\|other' "$TICKETS_LOG" && pass "no ticket lookup for a detached worktree or a non-ticket branch" || fail "no ticket lookup for a detached worktree or a non-ticket branch"
! grep -q 'ACM-1 ' "$GH_LOG" && ! grep -qx 'show ACM-1' "$TICKETS_LOG" && pass "work on origin: no PR or ticket lookup" || fail "work on origin: no PR or ticket lookup"

# Second run: nothing left to remove, the kept worktrees are listed again
out=$(prune)
! grep -q '^removed: ' <<<"$out" && [ "$(wc -l <<<"$out" | tr -d ' ')" -eq 8 ] && pass "second run: only the kept worktrees, listed again" || { fail "second run: only the kept worktrees, listed again"; echo "$out"; }

# The worktree the script runs in stays, even when finished
wt "$c" ACM-20 feature/ACM-20
out=$(cd "$w/ACM-20" && prune)
expect "current worktree: kept" "$out" "kept: $w/ACM-20 — current worktree"
[ -d "$w/ACM-20" ] && pass "current worktree: still there" || fail "current worktree: still there"

# Sessions unreadable: a finished worktree is kept, the other reasons still show
out=$(CLAUDE_FAIL=1 prune); rc=$?
[ $rc -eq 0 ] && pass "sessions unreadable: exit 0" || fail "sessions unreadable: exit 0, got $rc"
expect "sessions unreadable: finished worktree kept" "$out" "kept: $w/ACM-20 — sessions unknown"
expect "sessions unreadable: session's worktree kept" "$out" "kept: $w/ACM-9 — sessions unknown"
expect "sessions unreadable: other reasons unchanged" "$out" "kept: $w/ACM-4 — not finished"
[ -d "$w/ACM-20" ] && has_branch feature/ACM-20 && pass "sessions unreadable: nothing removed" || fail "sessions unreadable: nothing removed"
echo 'not json' > "$CLAUDE_AGENTS"
expect "sessions not a JSON list: finished worktree kept" "$(prune)" "kept: $w/ACM-20 — sessions unknown"
echo '[]' > "$CLAUDE_AGENTS"
expect "no sessions: finished worktree removed" "$(prune)" "removed: $w/ACM-20"

# Unlocked, the locked worktree goes like any finished one
git worktree unlock "$w/ACM-8"
expect "unlocked: removed" "$(prune)" "removed: $w/ACM-8"

# A board that is not GitHub: a closed ticket is not looked up; work on origin still counts
new_checkout jira 'board: jira' 'key: JRA'
c="$PROJECTS_ROOT/jira"; w="$c/.claude/worktrees"
wt "$c" JRA-1 feature/JRA-1; commit "$w/JRA-1"; echo CLOSED > "$TICKETS_DIR/JRA-1"
wt "$c" JRA-2 feature/JRA-2; commit "$w/JRA-2"; push "$w/JRA-2"
: > "$TICKETS_LOG"
out=$(cd "$c" && prune)
expect "other board: closed ticket does not finish the worktree" "$out" "kept: $w/JRA-1 — not finished"
expect "other board: work on origin does" "$out" "removed: $w/JRA-2"
[ ! -s "$TICKETS_LOG" ] && pass "other board: tickets.sh not called" || fail "other board: tickets.sh not called"

# GitHub board without a key: the ticket id is the issue number
new_checkout plain 'board: github' 'project: 5' 'repo: QuinnNei/plain'
c="$PROJECTS_ROOT/plain"; w="$c/.claude/worktrees"
wt "$c" 12 feature/12; commit "$w/12"; echo CLOSED > "$TICKETS_DIR/12"
expect "no key: closed ticket by number" "$(cd "$c" && prune)" "removed: $w/12"

# No origin: nothing counts as pushed
fixture_project_flat local 'board: none'
c="$PROJECTS_ROOT/local"; w="$c/.claude/worktrees"
wt "$c" x worktree-x
expect "no origin: kept" "$(cd "$c" && prune)" "kept: $w/x — not finished"

out=$(cd "$FIX" && prune 2>&1); rc=$?
[ $rc -eq 1 ] && pass "no git checkout: exit 1" || fail "no git checkout: exit 1, got $rc"
expect "no git checkout: named" "$out" "prune-worktrees.sh: $FIX is not in a git checkout"
out=$(cd "$c" && prune --force 2>&1); rc=$?
[ $rc -eq 1 ] && [ -d "$w/x" ] && pass "unknown option: exit 1, nothing removed" || fail "unknown option: exit 1, nothing removed"

done_testing
