#!/usr/bin/env bash
# tickets.sh, the board operations script: what it prints and which gh calls it makes (stand-in gh).
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work/tickets.sh"
fixture_new; fixture_gh
fixture_wiki acme 'board: github' 'project: 4' 'repo: QuinnNei/acme-wiki' 'owner: QuinnNei'
cd "$PROJECTS_ROOT/acme/acme" || exit 1
t() { bash "$SK" "$@"; }
bq() { printf 'api graphql -F owner=QuinnNei -F name=acme-wiki -F number=%s' "$1"; }

gh_can 'project item-list 4 --owner QuinnNei -L 200 --format json' '{"items":[
 {"id":"I1","status":"Todo","labels":[],"content":{"type":"Issue","number":1,"title":"Old plain","repository":"QuinnNei/acme-wiki"}},
 {"id":"I2","status":"Todo","labels":["urgent"],"content":{"type":"Issue","number":2,"title":"Urgent blocked","repository":"QuinnNei/acme-wiki"}},
 {"id":"I3","status":"Todo","labels":["urgent","bug"],"content":{"type":"Issue","number":3,"title":"Urgent free","repository":"QuinnNei/acme-wiki"}},
 {"id":"I4","status":"In Progress","labels":[],"content":{"type":"Issue","number":4,"title":"Claimed","repository":"QuinnNei/acme-wiki"}},
 {"id":"I5","status":"Todo","labels":[],"content":{"type":"Issue","number":5,"title":"Newer plain","repository":"QuinnNei/acme-wiki"}},
 {"id":"I6","status":"Todo","labels":[],"content":{"type":"Issue","number":6,"title":"Blocker closed","repository":"QuinnNei/acme-wiki"}}]}'
blk() { printf '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[%s]}}}}}' "$1"; }
gh_can "$(bq 1)" "$(blk '')"
gh_can "$(bq 2)" "$(blk '{"number":9,"state":"OPEN","repository":{"nameWithOwner":"QuinnNei/acme-code"}}')"
gh_can "$(bq 3)" "$(blk '')"
gh_can "$(bq 5)" "$(blk '')"
gh_can "$(bq 6)" "$(blk '{"number":1,"state":"CLOSED","repository":{"nameWithOwner":"QuinnNei/acme-wiki"}}')"

# list: To do only, no open blocker, urgent first, then lowest number
out=$(t list)
expect "list: urgent first" "$(sed -n 1p <<<"$out")" $'3\turgent,bug\tUrgent free'
expect "list: then oldest" "$(sed -n 2p <<<"$out")" $'1\t\tOld plain'
expect "list: closed blocker does not block" "$(sed -n 3p <<<"$out")" $'5\t\tNewer plain'
expect "list: closed blocker listed last" "$(sed -n 4p <<<"$out")" $'6\t\tBlocker closed'
expect "list: blocked and claimed tickets left out" "$(wc -l <<<"$out" | tr -d ' ')" "4"
expect "list: asks for 200 items" "$(gh_calls | head -1)" "project item-list 4 --owner QuinnNei -L 200 --format json"

# show: one JSON object
gh_can 'issue view 2 --repo QuinnNei/acme-wiki --json number,title,body,labels,comments,state' '{"number":2,"title":"Urgent blocked","body":"Text","state":"OPEN","labels":[{"name":"urgent"}],"comments":[{"author":{"login":"q"},"body":"hi"}]}'
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
gh_can 'issue create' 'https://github.com/QuinnNei/acme-wiki/issues/12'
gh_can 'issue view 12 --repo QuinnNei/acme-wiki --json id' '{"id":"ID12"}'
gh_can 'issue view 3 --repo QuinnNei/acme-wiki --json id' '{"id":"ID3"}'
gh_can 'issue view 9 --repo QuinnNei/acme-code --json id' '{"id":"ID9"}'
: > "$GH_LOG"
out=$(t create --title "New thing" --body "Body text" --label urgent,bug --blocked-by "3,QuinnNei/acme-code#9")
expect "create: prints the number" "$out" "12"
log=$(gh_calls)
expect "create: issue with labels" "$log" "issue create --repo QuinnNei/acme-wiki --title New thing --body Body text --label urgent --label bug"
expect "create: added to the Project" "$log" "project item-add 4 --owner QuinnNei --url https://github.com/QuinnNei/acme-wiki/issues/12"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID3 -f query=' <<<"$log" \
  && pass "create: blocked by own-repo ticket" || fail "create: blocked by own-repo ticket"
grep -q '^api graphql -F issueId=ID12 -F blockingIssueId=ID9 ' <<<"$log" \
  && pass "create: blocked by other-repo ticket" || fail "create: blocked by other-repo ticket"
: > "$GH_LOG"
t create --title "Plain" --body "b" >/dev/null
grep -q 'addBlockedBy\|--label' "$GH_LOG" && fail "create: no labels or blockers when none given" || pass "create: no labels or blockers when none given"

# close: with comment; not planned when no code
: > "$GH_LOG"
t close 5 --comment "Merged in a PR" >/dev/null
expect "close: comment" "$(gh_calls | tail -1)" "issue close 5 --repo QuinnNei/acme-wiki --comment Merged in a PR"
t close 6 --comment "No code needed" --not-planned >/dev/null
expect "close: not planned" "$(gh_calls | tail -1)" "issue close 6 --repo QuinnNei/acme-wiki --comment No code needed --reason not planned"

# no project: fails
cd "$FIX" && { t list >/dev/null 2>&1 && fail "no project: fails" || pass "no project: fails"; }
done_testing
