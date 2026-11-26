#!/usr/bin/env bash
# /send through claude -p on the GitHub board in the code repo (stand-in gh, project fixture), against a local bare remote.
# The git project's board has the key ACM (ids ACM-<n>, issue <n>); the project without git has none (ids are issue numbers).
# - Close: without a reason it asks; with one the issue closes as not planned with the reason.
# - PR: its body ends with `Closes <owner>/<repo>#<n>` and the sent ticket is not written to.
# - Follow-up: a leftover outside the ticket's change is filed as its own ticket, linked in the PR body above the
#   `Closes` line and named in the report; a reused PR whose body already links it files nothing.
# - A leftover from the handoff is fixed in its own commit.
# - Rebase onto a moved base, lint commit, test.sh, push and the "PR on <host> not supported" stop.
# - A ticket worktree is removed, port change and the ticket files /work wrote into it and all.
# - A failing test.sh is fixed in its own commit and the branch pushed.
# - Without git: the issue closes, ticket files deleted.
# A failing PR-step check keeps the run's record and gh calls in /tmp.
. "$(dirname "$0")/lib.sh"
fixture_new; fixture_gh
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Edit,Write,Bash(git *),Bash(bash *),Bash(PROJECTS_ROOT=*),Bash(VAULT=*),Bash(gh *),Bash(npm *),Bash(rm *),Bash(rmdir *),Bash(ls *),Bash(find *),Bash(cd *),Bash(claude agents *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}

setup() { fixture_claude_md "$1"; install_skill "$REPO_DIR/skills/send" send "$1"; }
# run_send <dir>: CLAUDE_OUT = every text the assistant printed
run_send() {
  run_claude "$1" "/t-send${2:+ $2}"
  CLAUDE_OUT=$(claude_said) KEPT=
}
# keep_run <label>: saves the last run's record (CLAUDE_RECORD) and gh calls as /tmp/live-send-<label>.*.jsonl and .gh.log,
# which stay after the fixture is removed, so a failure that comes once in many runs can be read afterwards. One save per run.
keep_run() {
  [ -z "$KEPT" ] && KEPT=$(mktemp "/tmp/live-send-$1.XXXXXX") && rm -f "$KEPT" \
    && cp "$CLAUDE_RECORD" "$KEPT.jsonl" && gh_calls > "$KEPT.gh.log"
  echo "     transcript: $KEPT.jsonl, gh calls: $KEPT.gh.log"
}
# only_line_commit <branch> <diff line>: a commit on the pushed branch whose whole diff is that one line
only_line_commit() {
  local c
  for c in $(git -C "$remote" rev-list "main..$1" 2>/dev/null); do
    [ "$(git -C "$remote" show --format= -U0 "$c" | grep -E '^[-+][^-+]')" = "$2" ] && echo "$c"
  done
}
# ticket <dir> <id> <slug> [base] [decisions]: .scratch ticket.md and handoff in <dir>, as /work writes them for a GitHub ticket (no branch line);
# the ref is the issue in the project's code repo. Without [decisions] the file has no `## Decisions` section.
ticket() {
  mkdir -p "$1/.scratch/$2-$3" "$1/.handoffs"
  { echo "# $2: Issue ${2##*-}"; echo; echo "ref: QuinnNei/$(basename "$1")#${2##*-}"; [ -z "${4:-}" ] || echo "base: $4"
    echo "board: github"; echo "Status: ready-for-agent"
    [ -z "${5:-}" ] || printf '\n## Decisions\n\n%s\n' "$5"; } > "$1/.scratch/$2-$3/ticket.md"
  echo "handoff $2" > "$1/.handoffs/HANDOFF-$2.md"
}
# board_writes: logged gh calls that change a ticket on the board
board_writes() { gh_calls | grep -E '^(issue close|issue edit|project item-edit)' || true; }

# --- git project with a local bare remote ---
# The origin is a local bare remote, so the settings name the code repo
fixture_project acme 'board: github' 'project: 4' 'repo: QuinnNei/acme' 'key: ACM'
fixture_note acme
acme="$PROJECTS_ROOT/acme/acme" remote="$FIX/acme.git"
git init -q --bare -b main "$remote"
git -C "$acme" remote add origin "$remote"
git -C "$acme" config user.name t; git -C "$acme" config user.email t@acme.test
# A git in front of the real one that reports a github.com origin while $FIX/github-origin exists; fetch and push still use the bare remote
REAL_GIT=$(command -v git)
cat > "$FIX/bin/git" <<SH
#!/usr/bin/env bash
if [ -f "$FIX/github-origin" ]; then
  case "\$*" in
    *get-url*origin|*"remote.origin.url") echo https://github.com/QuinnNei/acme.git; exit 0 ;;
    *"remote -v"|*"remote --verbose") printf 'origin\thttps://github.com/QuinnNei/acme.git (fetch)\norigin\thttps://github.com/QuinnNei/acme.git (push)\n'; exit 0 ;;
  esac
fi
exec "$REAL_GIT" "\$@"
SH
chmod +x "$FIX/bin/git"
setup "$acme"
mkdir -p "$acme/src"
echo 'var a = 1' > "$acme/src/a.js"
cat > "$acme/package.json" <<'JSON'
{ "name": "acme", "scripts": { "lint-fix": "sed -i.bak 's/^var /let /' src/*.js && rm src/*.bak" } }
JSON
echo '{ "version": "0.0.1", "configurations": [{ "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["start", "--", "--port", "5173"], "port": 5173 }] }' > "$acme/.claude/launch.json"
sed -i.bak 's/^var /let /' "$acme/src/a.js" && rm "$acme/src/a.js.bak"
# test.sh leaves a mark each time it runs, and fails while src/bad.js exists without its export line
cat > "$acme/test.sh" <<SH
#!/usr/bin/env bash
echo ran >> "$FIX/tests-ran"
[ ! -f src/bad.js ] || grep -qx 'module.exports = { bad }' src/bad.js || { echo 'FAIL src/bad.js lacks the line: module.exports = { bad }'; exit 1; }
SH
git -C "$acme" add -A && git -C "$acme" commit -qm "Add app" && git -C "$acme" push -q -u origin main 2>/dev/null

# Close: branch pushed, nothing on it. Without a reason it asks and changes nothing
git -C "$acme" checkout -q -b feature/ACM-11 && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-11 old-work main
run_send "$acme"
[ -z "$(board_writes)" ] && [ -f "$acme/.scratch/ACM-11-old-work/ticket.md" ] \
  && git -C "$remote" rev-parse -q --verify feature/ACM-11 >/dev/null \
  && pass "close without reason: nothing changed" || { fail "close without reason: nothing changed"; echo "$CLAUDE_OUT" | tail -20; }

# With a reason: the issue closes as not planned with the reason as its comment, branch gone locally and on origin, ticket files gone
run_send "$acme" "already fixed in the login rewrite"
w=$(board_writes)
[[ "$w" == 'issue close 11 --repo QuinnNei/acme --comment Closed without code: already fixed in the login rewrite --reason not planned' ]] \
  && pass "close: issue closed as not planned with the reason" || { fail "close: issue closed as not planned with the reason"; echo "$w"; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(git -C "$acme" branch --list feature/ACM-11)" ] && ! git -C "$remote" rev-parse -q --verify feature/ACM-11 >/dev/null \
  && pass "close: branch deleted locally and on origin" || fail "close: branch deleted locally and on origin"
[ ! -e "$acme/.scratch/ACM-11-old-work" ] && [ ! -e "$acme/.handoffs/HANDOFF-ACM-11.md" ] \
  && pass "close: ticket files deleted" || { fail "close: ticket files deleted"; echo "$CLAUDE_OUT" | tail -20; }
[ "$(git -C "$acme" rev-parse HEAD)" = "$(git -C "$acme" rev-parse origin/main)" ] \
  && pass "close: no commit, back on main" || fail "close: no commit, back on main"

# Committed and pushed, no PR yet, origin on github.com: the PR body ends with the Closes line, and nothing is written to the board
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b feature/ACM-13
echo 'let d = 4' > "$acme/src/d.js"
git -C "$acme" add src/d.js && git -C "$acme" commit -qm "Add d" && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-13 pushed-work main '- Keep d in its own file. Why: a.js is loaded on every page. Rejected: a line in a.js, it would grow the first load.'
# A leftover outside the ticket's change that breaks nothing, as the handoff reports it
echo 'Seen while working, outside this ticket and breaking nothing: README.md still names the old install command `make setup`.' >> "$acme/.handoffs/HANDOFF-ACM-13.md"
touch "$FIX/github-origin"
gh_can 'pr create' 'https://github.com/QuinnNei/acme/pull/7'
gh_can 'issue create' 'https://github.com/QuinnNei/acme/issues/31'
: > "$GH_LOG"
run_send "$acme"
rm -f "$FIX/github-origin"
! grep -qi 'nothing to send' <<<"$CLAUDE_OUT" && gh_calls | grep -q '^pr create ' \
  && pass "pushed commits: reach the PR step" || { fail "pushed commits: reach the PR step"; echo "$CLAUDE_OUT" | tail -20; keep_run github-pr; }
gh_calls | grep -qE '^Closes QuinnNei/acme#13( --[a-z].*)?$' && pass "PR body: ends with the Closes line" \
  || { fail "PR body: ends with the Closes line"; gh_calls; keep_run github-closes; }
[ -z "$(board_writes)" ] && pass "PR: no board write" || { fail "PR: no board write"; board_writes; }
[ -z "$(git -C "$acme" branch --list feature/ACM-13)" ] && [ ! -e "$acme/.scratch/ACM-13-pushed-work" ] \
  && pass "PR: branch and ticket files cleaned up" || { fail "PR: branch and ticket files cleaned up"; keep_run github-cleanup; }
grep -qxF -- '- Keep d in its own file. Why: a.js is loaded on every page. Rejected: a line in a.js, it would grow the first load.' "$VAULT"/raw/acme/*" ACM-13 "*.md 2>/dev/null \
  && pass "PR: the ticket's decision line is in its decision note" || { fail "PR: the ticket's decision line is in its decision note"; ls -R "$VAULT/raw" 2>&1; echo "$CLAUDE_OUT" | tail -20; }

gh_calls | grep -q '^issue create --repo QuinnNei/acme --title ' && gh_calls | grep -q '^project item-add 4 ' \
  && pass "follow-up: filed as a ticket on the Project" || { fail "follow-up: filed as a ticket on the Project"; gh_calls; echo "$CLAUDE_OUT" | tail -20; }
gh_calls | grep -q '^Follow-up: QuinnNei/acme#31 ' && pass "follow-up: PR body links the ticket" \
  || { fail "follow-up: PR body links the ticket"; gh_calls; }
! gh_calls | grep '^Follow-up:' | grep -qiE 'clos|fix|resolv' && pass "follow-up: its line has no closing keyword" \
  || { fail "follow-up: its line has no closing keyword"; gh_calls | grep '^Follow-up:'; }
# in the last body sent to gh, the follow-up line stands above the Closes line
f=$(gh_calls | grep -n '^Follow-up: ' | tail -1 | cut -d: -f1) c=$(gh_calls | grep -n '^Closes QuinnNei/acme#13' | tail -1 | cut -d: -f1)
[ -n "$f" ] && [ -n "$c" ] && [ "$f" -lt "$c" ] && pass "follow-up: its line stands before the Closes line" \
  || { fail "follow-up: its line stands before the Closes line"; gh_calls; }
grep -q 'ACM-31' <<<"$CLAUDE_OUT" && pass "follow-up: report names the ticket" || { fail "follow-up: report names the ticket"; echo "$CLAUDE_OUT" | tail -20; }

# Committed-but-unpushed work plus an uncommitted file; lint must cover both
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b bugfix/ACM-12 && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-12 login-fails main none
echo 'var b = 2' > "$acme/src/b.js"
git -C "$acme" add src/b.js && git -C "$acme" commit -qm "Add b"
echo 'var c = 3' > "$acme/src/c.js"
# main moves on origin after the branch was cut
git clone -q "$remote" "$FIX/elsewhere" 2>/dev/null
git -C "$FIX/elsewhere" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m "Merged elsewhere"
git -C "$FIX/elsewhere" push -q origin main 2>/dev/null
rm -f "$FIX/tests-ran"
# A leftover the ticket's change left unfinished, as the handoff reports it
echo 'Left unfinished by this ticket: src/b.js needs the extra last line `module.exports = { b }`.' >> "$acme/.handoffs/HANDOFF-ACM-12.md"
: > "$GH_LOG"
run_send "$acme"

grep -qF "PR on $remote not supported" <<<"$CLAUDE_OUT" && pass "non-GitHub origin: PR on <host> not supported" \
  || { fail "non-GitHub origin: PR on <host> not supported"; echo "$CLAUDE_OUT" | tail -20; keep_run local-stop; }
pushed=$(git -C "$remote" rev-parse bugfix/ACM-12 2>/dev/null)
[ -n "$pushed" ] && [ "$pushed" = "$(git -C "$acme" rev-parse HEAD)" ] && pass "push: remote has HEAD" || fail "push: remote has HEAD"
git -C "$remote" merge-base --is-ancestor main bugfix/ACM-12 2>/dev/null && pass "rebase: the pushed branch holds origin's new base commit" \
  || { fail "rebase: the pushed branch holds origin's new base commit"; git -C "$remote" log --oneline --all --graph | head; }
[ -s "$FIX/tests-ran" ] && pass "test: test.sh ran" || { fail "test: test.sh ran"; echo "$CLAUDE_OUT" | tail -20; }
[ "$(git -C "$remote" show bugfix/ACM-12:src/b.js 2>/dev/null | head -1)$(git -C "$remote" show bugfix/ACM-12:src/c.js 2>/dev/null)" = "let b = 2let c = 3" ] \
  && pass "lint: committed and uncommitted paths fixed" || fail "lint: committed and uncommitted paths fixed"
# The lint commit changes only var → let lines, in both files
lint=
for c in $(git -C "$remote" rev-list main..bugfix/ACM-12); do
  d=$(git -C "$remote" show --format= -U0 "$c" | grep -E '^[-+][^-+]')
  [ -n "$d" ] && ! grep -qvE '^[-+](var|let) [bc] = [23]$' <<<"$d" && [ "$(grep -c '^+let' <<<"$d")" = 2 ] && lint=$c
done
[ -n "$lint" ] && pass "lint: own commit" || { fail "lint: own commit"; git -C "$remote" log -p main..bugfix/ACM-12; }
[ -n "$(only_line_commit bugfix/ACM-12 '+module.exports = { b }')" ] && pass "leftover: fixed in its own commit" \
  || { fail "leftover: fixed in its own commit"; git -C "$remote" log -p main..bugfix/ACM-12; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(git -C "$acme" status --porcelain | grep -vE '\.(scratch|handoffs)/')" ] && pass "commit: tree clean" || fail "commit: tree clean"
[ -z "$(board_writes)" ] && pass "stop: no board write" || { fail "stop: no board write"; board_writes; }
[ "$(git -C "$acme" branch --show-current)" = bugfix/ACM-12 ] && [ -f "$acme/.scratch/ACM-12-login-fails/ticket.md" ] \
  && pass "stop: no cleanup" || { fail "stop: no cleanup"; keep_run local-cleanup; }
# The stop comes before the PR step: gh is asked nothing about PRs or labels
! gh_calls | grep -qE '^(pr|label) ' && pass "stop: no PR or label call" || { fail "stop: no PR or label call"; gh_calls; keep_run local-pr; }

# Ticket worktree no background session was started in, its ticket files inside it, with a dev server's port moved:
# the port change is dropped, the worktree removed
wt="$acme/.claude/worktrees/ACM-14"
git -C "$acme" checkout -q -B main origin/main
fixture_worktree "$acme" ACM-14 && git -C "$wt" push -q -u origin HEAD 2>/dev/null
ticket "$wt" ACM-14 worktree-ticket main
sed -i.bak 's/5173/5174/g' "$wt/.claude/launch.json" && rm "$wt/.claude/launch.json.bak"
run_send "$wt" "superseded by the rewrite"
[ ! -e "$wt" ] && ! git -C "$acme" worktree list | grep -qF "$wt" \
  && pass "worktree: removed with its port change" || { fail "worktree: removed with its port change"; git -C "$wt" status --short; echo "$CLAUDE_OUT" | tail -20; }
[ -z "$(git -C "$acme" branch --list feature/ACM-14)" ] && ! git -C "$remote" rev-parse -q --verify feature/ACM-14 >/dev/null \
  && pass "worktree: branch deleted locally and on origin" || fail "worktree: branch deleted locally and on origin"
gh_calls | grep -qF 'issue close 14 --repo QuinnNei/acme --comment Closed without code: superseded by the rewrite --reason not planned' && [ ! -e "$wt/.scratch/ACM-14-worktree-ticket" ] \
  && pass "worktree: issue closed as not planned, ticket files deleted" || { fail "worktree: issue closed as not planned, ticket files deleted"; gh_calls; }
# The ticket had no Decisions section and nothing on its branch: no stop, and the note holds only the close line
[ "$(grep -c '^- ' "$VAULT"/raw/acme/*" ACM-14 "*.md 2>/dev/null)" = 1 ] && grep -qxF -- '- Closed without code. Why: superseded by the rewrite. Rejected: none.' "$VAULT"/raw/acme/*" ACM-14 "*.md \
  && pass "close without a Decisions section: the note holds the close line alone" || { fail "close without a Decisions section: the note holds the close line alone"; ls -R "$VAULT/raw" 2>&1; echo "$CLAUDE_OUT" | tail -20; }

# A failing test.sh nobody reported: fixed in its own commit, then the branch is pushed with the tests green
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b feature/ACM-15
ticket "$acme" ACM-15 bad-change main none
echo 'let bad = 1' > "$acme/src/bad.js"
run_send "$acme"
[ -n "$(only_line_commit feature/ACM-15 '+module.exports = { bad }')" ] && pass "failing tests: fixed in its own commit" \
  || { fail "failing tests: fixed in its own commit"; git -C "$remote" log -p main..feature/ACM-15 2>&1 | head -40; echo "$CLAUDE_OUT" | tail -20; }
[ "$(git -C "$remote" show feature/ACM-15:test.sh 2>/dev/null)" = "$(git -C "$remote" show main:test.sh)" ] \
  && pass "failing tests: test.sh unchanged" || fail "failing tests: test.sh unchanged"

# The same leftover on a reused open PR whose body already links its ticket: no second ticket
git -C "$acme" checkout -q main && git -C "$acme" checkout -q -b feature/ACM-16
echo 'let e = 5' > "$acme/src/e.js"
git -C "$acme" add src/e.js && git -C "$acme" commit -qm "Add e" && git -C "$acme" push -q -u origin HEAD 2>/dev/null
ticket "$acme" ACM-16 resent-work main none
echo 'Seen while working, outside this ticket and breaking nothing: README.md still names the old install command `make setup`.' >> "$acme/.handoffs/HANDOFF-ACM-16.md"
touch "$FIX/github-origin"
pr8='{"url":"https://github.com/QuinnNei/acme/pull/8","state":"OPEN","body":"## Summary\n\n- Add e\n\nFollow-up: QuinnNei/acme#31 README.md still names the old install command `make setup`\nCloses QuinnNei/acme#16"}'
# the open PR answers both ways of asking for the branch's PR
gh_can 'pr view' "$pr8"
gh_can 'pr list --head feature/ACM-16' "[$pr8]"
: > "$GH_LOG"
run_send "$acme"
rm -f "$FIX/github-origin"
gh_calls | grep -qE '^pr (view|list --head)' && ! gh_calls | grep -qE '^(issue create|pr create)' \
  && pass "reused PR: linked follow-up not filed again" || { fail "reused PR: linked follow-up not filed again"; gh_calls; echo "$CLAUDE_OUT" | tail -20; }
grep -q 'ACM-31' <<<"$CLAUDE_OUT" && pass "reused PR: report names the earlier ticket" || { fail "reused PR: report names the earlier ticket"; echo "$CLAUDE_OUT" | tail -20; }

# --- project without git: two tickets, the one In Progress on the board is sent ---
fixture_project beta 'board: github' 'project: 5' 'repo: QuinnNei/beta'
fixture_note beta
beta="$PROJECTS_ROOT/beta/beta"
rm -rf "$beta/.git"
gh_can 'project item-list 5 --owner QuinnNei -L 200 --format json' '{"items":[
 {"id":"B1","status":"Todo","labels":[],"content":{"type":"Issue","number":22,"title":"Later","repository":"QuinnNei/beta"}},
 {"id":"B2","status":"In Progress","labels":[],"content":{"type":"Issue","number":21,"title":"Write the intro","repository":"QuinnNei/beta"}}]}'
gh_can 'issue view 21 --repo QuinnNei/beta' '{"number":21,"title":"Write the intro","body":"Two paragraphs.","state":"OPEN","labels":[],"comments":[]}'
gh_can 'issue view 22 --repo QuinnNei/beta' '{"number":22,"title":"Later","body":"","state":"OPEN","labels":[],"comments":[]}'
gh_can 'api graphql -F owner=QuinnNei -F name=beta' '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
setup "$beta"
ticket "$beta" 21 write-intro "" none
ticket "$beta" 22 later "" none
: > "$GH_LOG"
run_send "$beta"

[ "$(board_writes | sed 's/ --comment.*//')" = 'issue close 21 --repo QuinnNei/beta' ] \
  && pass "no git: the In Progress issue is closed" || { fail "no git: the In Progress issue is closed"; board_writes; echo "$CLAUDE_OUT" | tail -20; }
! board_writes | grep -q -- '--reason not planned' && pass "no git: closed as completed" || fail "no git: closed as completed"
[ ! -e "$beta/.scratch/21-write-intro" ] && [ ! -e "$beta/.handoffs/HANDOFF-21.md" ] \
  && pass "no git: ticket files deleted" || { fail "no git: ticket files deleted"; echo "$CLAUDE_OUT" | tail -20; }
[ -f "$beta/.scratch/22-later/ticket.md" ] && [ -f "$beta/.handoffs/HANDOFF-22.md" ] \
  && pass "no git: other ticket's files stay" || fail "no git: other ticket's files stay"
[ ! -e "$beta/.git" ] && pass "no git: no repo created" || fail "no git: no repo created"
done_testing
