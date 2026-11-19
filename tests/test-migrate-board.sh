#!/usr/bin/env bash
# migrate-board.sh: a vault board becomes issues (stand-in gh, fixture vault); a rerun creates nothing twice.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/new-project/migrate-board.sh"
fixture_new; fixture_gh
fixture_wiki acme 'board: github' 'project: 4' 'repo: QuinnNei/acme-wiki' 'owner: QuinnNei'
mkdir -p "$VAULT/Projects/Acme"
BOARD="$VAULT/Projects/Acme/Acme Board.md"
# Cards newest first, as the vault keeps them
{
  printf -- '---\n\nkanban-plugin: board\n\n---\n\n## To do\n\n'
  printf -- '- [ ] **ACM-1 · First, to do** #grilling #bug\n\tGoal: do the first thing.\n\tNeeds: ACM-2, OTH-9\n\tBranch `feature/ACM-1`\n\n'
  printf -- '## In progress\n\n- [ ] **ACM-2 · Second, claimed**\n\tNeeds: nothing\n\n'
  printf -- '## Frontier\n\n- [ ] **ACM-6 · Sixth, frontier**\n\n'
  printf -- '## Done\n\n- [x] **ACM-5 · Fifth, done** #bug\n\tGoal: shipped.\n\tPR https://github.com/o/acme/pull/4\n'
  printf -- '- [x] **[[ACM-4 Fourth, linked]]** #research\n\n'
  printf -- '%%%% kanban:settings\n```\n{"kanban-plugin":"board"}\n```\n%%%%\n'
} > "$BOARD"
cp "$BOARD" "$FIX/board.copy"

# Cards by number: ACM-1 is #1, ACM-2 #2, ACM-4 #3, ACM-5 #4, ACM-6 #5
gh_can 'repo view QuinnNei/acme-wiki' 'QuinnNei/acme-wiki'
gh_seq 'issue list' '[]' \
  '[{"number":1,"state":"OPEN","body":"was ACM-1\nx"},{"number":2,"state":"OPEN","body":"was ACM-2"},{"number":3,"state":"OPEN","body":"was ACM-4"},{"number":4,"state":"CLOSED","body":"was ACM-5"},{"number":5,"state":"OPEN","body":"was ACM-6"},{"number":9,"state":"OPEN","body":"Hand-made, no was line"}]'
gh_seq 'issue create' https://github.com/QuinnNei/acme-wiki/issues/1 https://github.com/QuinnNei/acme-wiki/issues/2 \
  https://github.com/QuinnNei/acme-wiki/issues/3 https://github.com/QuinnNei/acme-wiki/issues/4 https://github.com/QuinnNei/acme-wiki/issues/5
gh_can 'project item-list 4 --owner QuinnNei -L 200 --format json' '{"items":[{"id":"I2","status":"Todo","labels":[],"content":{"type":"Issue","number":2,"title":"x"}}]}'
gh_can 'project view 4 --owner QuinnNei --format json' '{"id":"PVT_1"}'
gh_can 'project field-list 4 --owner QuinnNei -L 200 --format json' '{"fields":[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]}]}'
gh_can 'issue view 1 --repo QuinnNei/acme-wiki --json id' '{"id":"ID1"}'
gh_can 'issue view 2 --repo QuinnNei/acme-wiki --json id' '{"id":"ID2"}'
gh_can 'issue view 1 --repo QuinnNei/acme-wiki --json number,title,body,labels,comments,state' '{"number":1,"title":"x","body":"","state":"OPEN","labels":[],"comments":[]}'
gh_seq 'api graphql -F owner=QuinnNei -F name=acme-wiki -F number=1' \
  '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}' \
  '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":2,"state":"OPEN","repository":{"nameWithOwner":"QuinnNei/acme-wiki"}}]}}}}}'

cd "$PROJECTS_ROOT/acme/acme" || exit 1
bash "$SK" "$BOARD" "$PROJECTS_ROOT/acme/acme" --owner QuinnNei >"$FIX/out" 2>"$FIX/err"; log=$(gh_calls)
creates=$(grep '^issue create' <<<"$log")
flat=$(tr '\n' '~' <<<"$log")   # bodies span lines
expect "board made first" "$(sed -n 1p <<<"$log")" "repo view QuinnNei/acme-wiki --json nameWithOwner --jq .nameWithOwner"
expect "one issue per card" "$(wc -l <<<"$creates" | tr -d ' ')" "5"
expect "lowest card number first, body starts with the was line" "$(sed -n 1p <<<"$creates" | cut -c1-90)" "issue create --repo QuinnNei/acme-wiki --title First, to do --body was ACM-1"
expect "highest card number last" "$(sed -n 5p <<<"$creates" | cut -c1-69)" "issue create --repo QuinnNei/acme-wiki --title Sixth, frontier --body"
grep -q -- 'title First, to do --body was ACM-1~.* --label grilling --label bug~' <<<"$flat" \
  && pass "tags become labels" || fail "tags become labels"
grep -q -- '--title Fourth, linked --body was ACM-4' <<<"$creates" \
  && pass "wiki-link card: title without brackets and id" || fail "wiki-link card: title without brackets and id"
grep -q -- '--title Sixth, frontier .*--label Frontier$' <<<"$creates" \
  && pass "other column: column name as label" || fail "other column: column name as label"
expect "column label is created" "$log" "label create Frontier --repo QuinnNei/acme-wiki --force"
expect "a label is made once" "$(grep -c '^label create bug --repo' <<<"$log")" "2"   # once by board.sh, once by the migration
grep -q 'was ACM-1~Goal: do the first thing.~Needs: ACM-2, OTH-9~' <<<"$flat" && pass "Needs line stays in the body" || fail "Needs line stays in the body"
grep -q 'Branch `feature/ACM-1` --label' <<<"$flat" && pass "Branch line stays as text" || fail "Branch line stays as text"
grep -q 'was ACM-5~Goal: shipped.~PR https://github.com/o/acme/pull/4 --label bug~' <<<"$flat" && pass "PR line stays as text" || fail "PR line stays as text"
expect "In progress sets the Status" "$log" "project item-edit --id I2 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
expect "Done closes the issue" "$log" "issue close 4 --repo QuinnNei/acme-wiki --comment Done on the vault board (was ACM-5)."
expect "Done closes the linked card too" "$log" "issue close 3 --repo QuinnNei/acme-wiki --comment Done on the vault board (was ACM-4)."
expect "To do, In progress and other columns stay open" "$(grep -c '^issue close' <<<"$log")" "2"
expect "Needs becomes blocked-by through the old ids" "$(grep -c '^api graphql -F issueId=ID1 -F blockingIssueId=ID2 ' <<<"$log")" "1"
expect "no other blocked-by link" "$(grep -c 'issueId=' <<<"$log")" "1"
grep -q 'ACM-1 needs OTH-9' "$FIX/err" && pass "id from another board is reported" || fail "id from another board is reported"
[ ! -e "$BOARD" ] && [ -f "$VAULT/Archive/Acme Board.md" ] && pass "board file moved to the vault's Archive" || fail "board file moved to the vault's Archive"
cmp -s "$VAULT/Archive/Acme Board.md" "$FIX/board.copy" && pass "archived file is unchanged" || fail "archived file is unchanged"

# Rerun: the issues exist (#3 still open, as after a failed run), nothing is created twice
rm "$VAULT/Archive/Acme Board.md"; cp "$FIX/board.copy" "$BOARD"; : > "$GH_LOG"
bash "$SK" "$BOARD" "$PROJECTS_ROOT/acme/acme" --owner QuinnNei >"$FIX/out2" 2>/dev/null; log=$(gh_calls)
expect "rerun: no issue created" "$(grep -c '^issue create' <<<"$log")" "0"
expect "rerun: no blocked-by added twice" "$(grep -c 'issueId=' <<<"$log")" "0"
expect "rerun: finishes the open Done issue" "$(grep '^issue close' <<<"$log")" "issue close 3 --repo QuinnNei/acme-wiki --comment Done on the vault board (was ACM-4)."
expect "rerun: reports the cards kept" "$(grep -c '^kept' "$FIX/out2")" "5"
[ -f "$VAULT/Archive/Acme Board.md" ] && pass "rerun: archived again" || fail "rerun: archived again"
done_testing
