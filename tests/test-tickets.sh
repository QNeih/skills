#!/usr/bin/env bash
# tickets.sh, the board operations script: what it prints and which gh calls it makes (stand-in gh),
# on issues in the code repo, with and without a key in the ticket ids.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work/tickets.sh"
fixture_new; fixture_gh
# No repo and owner settings: both come from the checkout's origin
fixture_project acme 'board: github' 'project: 4'
git -C "$PROJECTS_ROOT/acme/acme" remote add origin https://github.com/QuinnNei/acme.git
cd "$PROJECTS_ROOT/acme/acme" || exit 1
t() { bash "$SK" "$@"; }
bq() { printf 'api graphql -F owner=QuinnNei -F name=acme -F number=%s' "$1"; }

gh_can 'project item-list 4 --owner QuinnNei -L 200 --format json' '{"items":[
 {"id":"I1","status":"Todo","labels":[],"content":{"type":"Issue","number":1,"title":"Old plain","repository":"QuinnNei/acme"}},
 {"id":"I2","status":"Todo","labels":["urgent"],"content":{"type":"Issue","number":2,"title":"Urgent blocked","repository":"QuinnNei/acme"}},
 {"id":"I3","status":"Todo","labels":["urgent","bug"],"content":{"type":"Issue","number":3,"title":"Urgent free","repository":"QuinnNei/acme"}},
 {"id":"I4","status":"In Progress","labels":[],"content":{"type":"Issue","number":4,"title":"Claimed","repository":"QuinnNei/acme"}},
 {"id":"I5","status":"Todo","labels":[],"content":{"type":"Issue","number":5,"title":"Newer plain","repository":"QuinnNei/acme"}},
 {"id":"I6","status":"Todo","labels":[],"content":{"type":"Issue","number":6,"title":"Blocker closed","repository":"QuinnNei/acme"}}]}'
blk() { printf '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[%s]}}}}}' "$1"; }
gh_can "$(bq 1)" "$(blk '')"
gh_can "$(bq 2)" "$(blk '{"number":9,"state":"OPEN","repository":{"nameWithOwner":"QuinnNei/acme-code"}}')"
gh_can "$(bq 3)" "$(blk '')"
gh_can "$(bq 5)" "$(blk '')"
gh_can "$(bq 6)" "$(blk '{"number":1,"state":"CLOSED","repository":{"nameWithOwner":"QuinnNei/acme"}}')"

# list: To do only, no open blocker, urgent first, then lowest number
out=$(t list)
expect "list: urgent first" "$(sed -n 1p <<<"$out")" $'3\turgent,bug\tUrgent free'
expect "list: then oldest" "$(sed -n 2p <<<"$out")" $'1\t\tOld plain'
expect "list: closed blocker does not block" "$(sed -n 3p <<<"$out")" $'5\t\tNewer plain'
expect "list: closed blocker listed last" "$(sed -n 4p <<<"$out")" $'6\t\tBlocker closed'
expect "list: blocked and claimed tickets left out" "$(wc -l <<<"$out" | tr -d ' ')" "4"
expect "list: asks for 200 items" "$(gh_calls | head -1)" "project item-list 4 --owner QuinnNei -L 200 --format json"

# show: one JSON object
gh_can 'issue view 2 --repo QuinnNei/acme --json number,title,body,labels,comments,state' '{"number":2,"title":"Urgent blocked","body":"Text","state":"OPEN","labels":[{"name":"urgent"}],"comments":[{"author":{"login":"q"},"body":"hi"}]}'
out=$(t show 2)
expect "show: number" "$(jq -c .number <<<"$out")" "2"
expect "show: body" "$(jq -r .body <<<"$out")" "Text"
expect "show: labels as names" "$(jq -c .labels <<<"$out")" '["urgent"]'
expect "show: comments" "$(jq -c .comments <<<"$out")" '[{"author":"q","body":"hi"}]'
expect "show: blockers" "$(jq -c .blockers <<<"$out")" '[{"ref":"QuinnNei/acme-code#9","state":"OPEN"}]'
expect "show: status from the Project" "$(jq -r .status <<<"$out")" "Todo"
expect "show: state" "$(jq -r .state <<<"$out")" "OPEN"

# status: option ids from the Project's Status field
gh_can 'project view 4 --owner QuinnNei --format json' '{"id":"PVT_1"}'
gh_can 'project field-list 4 --owner QuinnNei -L 200 --format json' '{"fields":[{"id":"F0","name":"Title"},{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]}]}'
out=$(t status 5 in-progress)
expect "status: prints the result" "$out" "5: In Progress"
expect "status: edits the item" "$(gh_calls | tail -1)" "project item-edit --id I5 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
t status 5 Done >/dev/null
expect "status: Done option" "$(gh_calls | tail -1)" "project item-edit --id I5 --project-id PVT_1 --field-id F1 --single-select-option-id O3"
t status 5 later >/dev/null 2>&1 && fail "status: unknown name fails" || pass "status: unknown name fails"

# create: issue, Project item, blockers (own-repo number and other-repo ref)
gh_can 'issue create' 'https://github.com/QuinnNei/acme/issues/12'
gh_can 'issue view 12 --repo QuinnNei/acme --json id' '{"id":"ID12"}'
gh_can 'issue view 3 --repo QuinnNei/acme --json id' '{"id":"ID3"}'
gh_can 'issue view 9 --repo QuinnNei/acme-code --json id' '{"id":"ID9"}'
: > "$GH_LOG"
out=$(t create --title "New thing" --body "Body text" --label urgent,bug --blocked-by "3,QuinnNei/acme-code#9")
expect "create: prints the number" "$out" "12"
log=$(gh_calls)
expect "create: issue with labels" "$log" "issue create --repo QuinnNei/acme --title New thing --body Body text --label urgent --label bug"
expect "create: added to the Project" "$log" "project item-add 4 --owner QuinnNei --url https://github.com/QuinnNei/acme/issues/12"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID3 -f query=' <<<"$log" \
  && pass "create: blocked by own-repo ticket" || fail "create: blocked by own-repo ticket"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID9 ' <<<"$log" \
  && pass "create: blocked by other-repo ticket" || fail "create: blocked by other-repo ticket"
: > "$GH_LOG"
t create --title "Plain" --body "b" >/dev/null
# the issue is created but adding it to the Project fails: the error names the issue
mkdir -p "$FIX/failbin"
printf '#!/usr/bin/env bash\ncase "$*" in "project item-add"*) echo "gh: no access" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$FIX/bin/gh" > "$FIX/failbin/gh"
chmod +x "$FIX/failbin/gh"
err=$(PATH="$FIX/failbin:$PATH" t create --title "Half" --body "b" 2>&1) && fail "create: a failed Project add fails" \
  || expect "create: a failed Project add names the created issue" "$err" "tickets.sh: create: issue 12 exists (https://github.com/QuinnNei/acme/issues/12) but was not added to Project 4"
grep -q 'addBlockedBy\|--label' "$GH_LOG" && fail "create: no labels or blockers when none given" || pass "create: no labels or blockers when none given"

# close: with comment; not planned when no code
: > "$GH_LOG"
t close 5 --comment "Merged in a PR" >/dev/null
expect "close: comment" "$(gh_calls | tail -1)" "issue close 5 --repo QuinnNei/acme --comment Merged in a PR"
t close 6 --comment "No code needed" --not-planned >/dev/null
expect "close: not planned" "$(gh_calls | tail -1)" "issue close 6 --repo QuinnNei/acme --comment No code needed --reason not planned"

# block: one blocker on an existing ticket
: > "$GH_LOG"
out=$(t block 12 3)
expect "block: prints the result" "$out" "12: blocked by 3"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID3 -f query=' <<<"$(gh_calls)" \
  && pass "block: adds the blocked-by link" || fail "block: adds the blocked-by link"

# edit: title, body or both on the issue; no flag fails before any gh call
: > "$GH_LOG"
expect "edit: title only prints the result" "$(t edit 5 --title "New title")" "5: edited"
expect "edit: title only" "$(gh_calls | tail -1)" "issue edit 5 --repo QuinnNei/acme --title New title"
expect "edit: body only" "$(t edit 5 --body "New body" >/dev/null; gh_calls | tail -1)" "issue edit 5 --repo QuinnNei/acme --body New body"
expect "edit: title and body" "$(t edit '#5' --title T --body B >/dev/null; gh_calls | tail -1)" "issue edit 5 --repo QuinnNei/acme --title T --body B"
expect "edit: an empty body clears it" "$(t edit 5 --body "" >/dev/null; gh_calls | tail -1)" "issue edit 5 --repo QuinnNei/acme --body "
: > "$GH_LOG"
err=$(t edit 5 2>&1) && fail "edit: no flag fails" || expect "edit: no flag says how" "$err" "tickets.sh: edit: give --title, --body or both"
err=$(t edit 5 --title "" 2>&1) && fail "edit: an empty title fails" || expect "edit: an empty title says why" "$err" "tickets.sh: edit: --title must not be empty"
t edit 5 --label x >/dev/null 2>&1 && fail "edit: unknown flag fails" || pass "edit: unknown flag fails"
expect "edit: a refused call reaches no gh call" "$([ -z "$(gh_calls)" ] && echo none)" "none"

# a full item list (200) without the ticket: fails loudly, never "not on the Project"
fixture_project_flat big 'board: github' 'project: 8' 'repo: QuinnNei/big'
gh_can 'project item-list 8 --owner QuinnNei -L 200 --format json' "$(jq -nc '{items: [range(1; 201) | {id: "X\(.)", status: "Todo", labels: [], content: {type: "Issue", number: ., title: "t"}}]}')"
gh_can 'issue view 500 --repo QuinnNei/big --json number,title,body,labels,comments,state' '{"number":500,"title":"x","body":"","state":"OPEN","labels":[],"comments":[]}'
gh_can 'api graphql -F owner=QuinnNei -F name=big -F number=500' "$(blk '')"
cd "$PROJECTS_ROOT/big" || exit 1
limit="tickets.sh: ticket 500 not found in the first 200 Project items: the board exceeds the item-list limit"
err=$(t status 500 done 2>&1) && fail "full list: status fails" || expect "full list: status names the limit" "$err" "$limit"
err=$(t show 500 2>&1) && fail "full list: show fails" || expect "full list: show names the limit" "$err" "$limit"

# Ticket ids. Without a key setting: <n> and #<n>; a keyed id is refused
cd "$PROJECTS_ROOT/acme/acme" || exit 1
: > "$GH_LOG"
expect "no key: #<n> is the number" "$(t status '#5' done)" "5: Done"
err=$(t show ACM-2 2>&1) && fail "no key: a keyed id fails" || expect "no key: a keyed id says why" "$err" "tickets.sh: ACM-2 is no ticket of this board: its tickets are plain numbers"
# With a key: <KEY>-<n>, #<n> and <n> name the same issue; output stays the number
bash "$REPO_DIR/skills/work/board.sh" set . key ACM >/dev/null
expect "key: <KEY>-<n> shows the issue" "$(t show ACM-2 | jq -c .number)" "2"
expect "key: status takes <KEY>-<n>, prints the number" "$(t status ACM-5 in-progress)" "5: In Progress"
expect "key: the bare number still works" "$(t status 5 todo)" "5: Todo"
: > "$GH_LOG"
expect "key: close takes <KEY>-<n>" "$(t close ACM-6 --comment "Done")" "closed: 6"
expect "key: close reaches the issue number" "$(gh_calls | tail -1)" "issue close 6 --repo QuinnNei/acme --comment Done"
: > "$GH_LOG"
expect "key: block takes keyed ids" "$(t block ACM-12 ACM-3)" "12: blocked by ACM-3"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID3 -f query=' <<<"$(gh_calls)" \
  && pass "key: block links the two issues" || fail "key: block links the two issues"
out=$(t create --title "Keyed" --body "b" --blocked-by "ACM-3")
expect "key: create prints the number" "$out" "12"
: > "$GH_LOG"
expect "key: edit takes <KEY>-<n>, prints the number" "$(t edit ACM-5 --title T)" "5: edited"
expect "key: edit reaches the issue number" "$(gh_calls | tail -1)" "issue edit 5 --repo QuinnNei/acme --title T"
: > "$GH_LOG"
err=$(t close OTH-6 --comment x 2>&1) && fail "key: another board's id fails" || expect "key: another board's id says why" "$err" "tickets.sh: OTH-6 is no ticket of this board (key ACM)"
err=$(t edit OTH-5 --title T 2>&1) && fail "key: edit refuses another board's id" || expect "key: edit says why it refuses another board's id" "$err" "tickets.sh: OTH-5 is no ticket of this board (key ACM)"
err=$(t show ACM-x 2>&1) && fail "key: an id without a number fails" || pass "key: an id without a number fails"
expect "key: a refused id reaches no gh call" "$([ -z "$(gh_calls)" ] && echo none)" "none"

# no board yet: fails with the lookup's reason
fixture_repo "$PROJECTS_ROOT/bare"
cd "$PROJECTS_ROOT/bare" || exit 1
err=$(t list 2>&1) && fail "no settings: fails" || expect "no settings: says the board step has not run" "$err" "tickets.sh: no settings file $PROJECTS_ROOT/bare/.claude/project.md: the board step has not run"
# a Jira board: fails
fixture_project_flat jira 'board: jira' 'key: CON'
cd "$PROJECTS_ROOT/jira" && { err=$(t list 2>&1) && fail "jira board: fails" || expect "jira board: says so" "$err" "tickets.sh: board is jira, not github"; }
# settings without the Project's number: fails
fixture_project_flat half 'board: github' 'repo: QuinnNei/half'
cd "$PROJECTS_ROOT/half" && { t list >/dev/null 2>&1 && fail "no Project number: fails" || pass "no Project number: fails"; }
# no project: fails
cd "$FIX" && { t list >/dev/null 2>&1 && fail "no project: fails" || pass "no project: fails"; }
done_testing
