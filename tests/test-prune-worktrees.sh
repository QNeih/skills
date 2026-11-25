#!/usr/bin/env bash
# work/prune-worktrees.sh: which worktrees of a fixture checkout it removes, with their local
# branches, and which it lists and leaves alone. Stand-ins: gh (merged PRs) and claude (sessions),
# so no real worktree, PR or session is read or changed.
. "$(dirname "$0")/lib.sh"
fixture_new; fixture_gh
prune() { bash "$REPO_DIR/skills/work/prune-worktrees.sh" "$@"; }

# A gh that fails, for PATH="$FIX/failbin:$PATH"
mkdir -p "$FIX/failbin"; printf '#!/usr/bin/env bash\necho "gh: not logged in" >&2; exit 1\n' > "$FIX/failbin/gh"; chmod +x "$FIX/failbin/gh"
# Stand-in claude: `agents` prints $CLAUDE_AGENTS, or fails when $CLAUDE_FAIL is set; logs each call
export CLAUDE_AGENTS="$FIX/agents.json" CLAUDE_LOG="$FIX/claude.log"; echo '[]' > "$CLAUDE_AGENTS"; : > "$CLAUDE_LOG"
cat > "$FIX/bin/claude" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
[ -z "${CLAUDE_FAIL:-}" ] || { echo "no sessions" >&2; exit 1; }
cat "$CLAUDE_AGENTS"
SH
chmod +x "$FIX/bin/claude"
g() { git -c user.name=t -c user.email=t@acme.test "$@"; }

# new_checkout <name> <origin dir>: checkout with an origin holding main and a .gitignore.
# An origin under $FIX/github.com/ reads as a GitHub URL; any other folder as another host.
new_checkout() {
  local c="$PROJECTS_ROOT/$1"
  fixture_repo "$c"
  printf '.scratch/\n.handoffs/\n' > "$c/.gitignore"
  g -C "$c" add .gitignore; g -C "$c" commit -q -m ignore
  mkdir -p "$2"; git init -q --bare --template= "$2/$1.git"
  git -C "$c" remote add origin "$2/$1.git"
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
# merged <worktree> <branch>: gh lists a merged PR whose head commit is the worktree's tip
merged() { gh_can "pr list --head $2 --state merged" "[{\"headRefOid\":\"$(git -C "$1" rev-parse HEAD)\"}]"; }
has_branch() { git -C "$c" rev-parse -q --verify "refs/heads/$1" >/dev/null; }

new_checkout acme "$FIX/github.com"
c="$PROJECTS_ROOT/acme"; w="$c/.claude/worktrees"
gh_can 'pr list --head' '[]'
# Ticket branches: only a merged PR at the tip finishes them
wt "$c" ACM-1 feature/ACM-1; commit "$w/ACM-1"; push "$w/ACM-1"                      # open ticket, all pushed
wt "$c" ACM-2 feature/ACM-2; commit "$w/ACM-2"; merged "$w/ACM-2" feature/ACM-2      # merged PR at the tip, squash-merged
wt "$c" ACM-3 bugfix/ACM-3; commit "$w/ACM-3"; push "$w/ACM-3"; merged "$w/ACM-3" bugfix/ACM-3
wt "$c" ACM-12 hotfix/ACM-12; commit "$w/ACM-12"                                     # merged PR of an older tip
gh_can 'pr list --head hotfix/ACM-12 --state merged' '[{"headRefOid":"0000000000000000000000000000000000000000"}]'
wt "$c" ACM-4 feature/ACM-4; commit "$w/ACM-4"                                       # unpushed, no PR
wt "$c" ACM-5 feature/ACM-5; merged "$w/ACM-5" feature/ACM-5; echo changed >> "$w/ACM-5/.gitignore" # modified tracked file
wt "$c" ACM-6 feature/ACM-6; merged "$w/ACM-6" feature/ACM-6; echo new > "$w/ACM-6/notes.txt"       # untracked file
wt "$c" ACM-7 feature/ACM-7; merged "$w/ACM-7" feature/ACM-7                         # ignored ticket files only
mkdir -p "$w/ACM-7/.scratch/ACM-7-x" "$w/ACM-7/.handoffs"; echo t > "$w/ACM-7/.scratch/ACM-7-x/ticket.md"; echo h > "$w/ACM-7/.handoffs/HANDOFF-ACM-7.md"
wt "$c" ACM-8 feature/ACM-8; merged "$w/ACM-8" feature/ACM-8; git -C "$c" worktree lock "$w/ACM-8"  # locked
wt "$c" ACM-9 feature/ACM-9; merged "$w/ACM-9" feature/ACM-9                         # a session's worktree
wt "$c" ACM-90 feature/ACM-90; merged "$w/ACM-90" feature/ACM-90                     # shares the session's name prefix
# Every other worktree: commits on origin are enough
wt "$c" agent-a1 worktree-agent-a1                                                   # nothing of its own
wt "$c" agent-a2 worktree-agent-a2; commit "$w/agent-a2"                             # own commit, unpushed
wt "$c" agent-a3 worktree-agent-a3; commit "$w/agent-a3"; push "$w/agent-a3"         # own commit, pushed
wt "$c" agent-a4 worktree-agent-a4; commit "$w/agent-a4"; merged "$w/agent-a4" worktree-agent-a4   # unpushed, merged PR
wt "$c" det-1 --detach                                                               # detached, on origin
wt "$c" det-2 --detach; commit "$w/det-2"                                            # detached, own commit
printf '[{"id":"s9","cwd":"%s","kind":"background","state":"done"},{"id":"s0","cwd":"%s","kind":"background","state":"blocked"}]\n' "$w/ACM-9" "$c" > "$CLAUDE_AGENTS"
cd "$c" || exit 1

want="kept: $w/ACM-1 — not finished
removed: $w/ACM-2
removed: $w/ACM-3
kept: $w/ACM-12 — commits after the merged PR
kept: $w/ACM-4 — not finished
kept: $w/ACM-5 — uncommitted changes
kept: $w/ACM-6 — uncommitted changes
removed: $w/ACM-7
kept: $w/ACM-8 — locked
claude rm s9 — $w/ACM-9
removed: $w/ACM-90
removed: $w/agent-a1
kept: $w/agent-a2 — not finished
removed: $w/agent-a3
removed: $w/agent-a4
removed: $w/det-1
kept: $w/det-2 — not finished"
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
for n in ACM-2 ACM-3 ACM-7 ACM-90 agent-a1 agent-a3 agent-a4 det-1; do
  [ ! -e "$w/$n" ] && pass "$n: worktree removed" || fail "$n: worktree removed"
done
for b in feature/ACM-2 bugfix/ACM-3 feature/ACM-7 feature/ACM-90 worktree-agent-a1 worktree-agent-a3 worktree-agent-a4; do
  ! has_branch "$b" && pass "$b: local branch deleted" || fail "$b: local branch deleted"
done
for n in ACM-1 ACM-12 ACM-4 ACM-5 ACM-6 ACM-8 ACM-9 agent-a2 det-2; do
  [ -d "$w/$n" ] && pass "$n: worktree kept" || fail "$n: worktree kept"
done
for b in feature/ACM-1 hotfix/ACM-12 feature/ACM-4 feature/ACM-5 feature/ACM-6 feature/ACM-8 feature/ACM-9 worktree-agent-a2 main; do
  has_branch "$b" && pass "$b: local branch kept" || fail "$b: local branch kept"
done
[ -f "$w/ACM-6/notes.txt" ] && grep -q changed "$w/ACM-5/.gitignore" && pass "uncommitted work untouched" || fail "uncommitted work untouched"
expect "sessions read for the main checkout" "$(cat "$CLAUDE_LOG")" "agents --json --all --cwd $c"
expect "merged PR looked up by branch" "$(gh_calls)" "pr list --head feature/ACM-2 --state merged --json headRefOid"
! grep -q 'worktree-agent-a[13] ' "$GH_LOG" && pass "non-ticket branch on origin: no PR lookup" || fail "non-ticket branch on origin: no PR lookup"

# Second run: nothing left to remove, the kept worktrees are listed again
out=$(prune)
! grep -q '^removed: ' <<<"$out" && [ "$(wc -l <<<"$out" | tr -d ' ')" -eq 9 ] && pass "second run: only the kept worktrees, listed again" || { fail "second run: only the kept worktrees, listed again"; echo "$out"; }

# A PR lookup that fails is named as the reason
expect "gh fails: named" "$(PATH="$FIX/failbin:$PATH" prune --dry-run)" "kept: $w/ACM-4 — PR lookup failed: gh: not logged in"

# --dry-run fetches first: a branch origin holds, unknown to the local origin refs, counts as pushed
wt "$c" agent-f worktree-agent-f; commit "$w/agent-f"; push "$w/agent-f"
git update-ref -d refs/remotes/origin/worktree-agent-f
expect "dry run: verdict from fetched refs" "$(prune --dry-run)" "removed: $w/agent-f"
[ -d "$w/agent-f" ] && pass "dry run after fetch: still there" || fail "dry run after fetch: still there"
expect "real run agrees with the dry run" "$(prune)" "removed: $w/agent-f"

# The worktree the script runs in stays, even when finished
wt "$c" ACM-20 feature/ACM-20; merged "$w/ACM-20" feature/ACM-20
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

# Origin on another host: no PR lookup, so ticket branches stay; commits on origin still count elsewhere
new_checkout devops "$FIX/dev.azure.test"
c="$PROJECTS_ROOT/devops"; w="$c/.claude/worktrees"
wt "$c" 1234 feature/1234; commit "$w/1234"; push "$w/1234"; merged "$w/1234" feature/1234
wt "$c" agent-b1 worktree-agent-b1; commit "$w/agent-b1"; push "$w/agent-b1"
wt "$c" agent-b2 worktree-agent-b2; commit "$w/agent-b2"
: > "$GH_LOG"
out=$(cd "$c" && PATH="$FIX/failbin:$PATH" prune)
expect "other host: ticket branch kept" "$out" "kept: $w/1234 — not finished"
expect "other host: pushed non-ticket worktree removed" "$out" "removed: $w/agent-b1"
expect "other host: unpushed non-ticket worktree kept, no lookup failure" "$out" "kept: $w/agent-b2 — not finished"
[ ! -s "$GH_LOG" ] && ! grep -q 'PR lookup' <<<"$out" && pass "other host: gh never called" || { fail "other host: gh never called"; cat "$GH_LOG"; }

# Origin unreachable: commits on the stale origin refs don't finish a worktree; a merged PR does
new_checkout gone "$FIX/github.com"
c="$PROJECTS_ROOT/gone"; w="$c/.claude/worktrees"
wt "$c" agent-g1 worktree-agent-g1; commit "$w/agent-g1"; push "$w/agent-g1"
wt "$c" GON-2 feature/GON-2; commit "$w/GON-2"; merged "$w/GON-2" feature/GON-2
wt "$c" GON-3 --detach
wt "$c" GON-4 feature/GON-4; commit "$w/GON-4"; push "$w/GON-4"
git -C "$c" remote set-url origin "$FIX/github.com/missing.git"
out=$(cd "$c" && prune); rc=$?
[ $rc -eq 0 ] && pass "fetch fails: exit 0" || fail "fetch fails: exit 0, got $rc"
grep -q "^kept: $w/agent-g1 — fetch failed: .*missing.git" <<<"$out" && pass "fetch fails: pushed non-ticket worktree kept, git's message named" || { fail "fetch fails: pushed non-ticket worktree kept, git's message named"; echo "$out"; }
grep -q "^kept: $w/GON-3 — fetch failed: " <<<"$out" && pass "fetch fails: detached worktree kept" || { fail "fetch fails: detached worktree kept"; echo "$out"; }
expect "fetch fails: merged PR at the branch tip still finishes" "$out" "removed: $w/GON-2"
expect "fetch fails: a ticket branch does not depend on the fetch" "$out" "kept: $w/GON-4 — not finished"

# No origin: nothing counts as pushed
fixture_repo "$PROJECTS_ROOT/local"
c="$PROJECTS_ROOT/local"; w="$c/.claude/worktrees"
wt "$c" x worktree-x
expect "no origin: kept" "$(cd "$c" && prune)" "kept: $w/x — not finished"

out=$(cd "$FIX" && prune 2>&1); rc=$?
[ $rc -eq 1 ] && pass "no git checkout: exit 1" || fail "no git checkout: exit 1, got $rc"
expect "no git checkout: named" "$out" "prune-worktrees.sh: $FIX is not in a git checkout"
out=$(cd "$c" && prune --force 2>&1); rc=$?
[ $rc -eq 1 ] && [ -d "$w/x" ] && pass "unknown option: exit 1, nothing removed" || fail "unknown option: exit 1, nothing removed"

done_testing
