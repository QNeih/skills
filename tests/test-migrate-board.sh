#!/usr/bin/env bash
# migrate-board.sh: a vault board becomes issues in the code repo on a board keyed like the cards
# (stand-in gh, fixture vault); a rerun creates nothing twice.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/new-project/migrate-board.sh"
fixture_new; fixture_gh
# No settings file yet: the migration makes the board first
fixture_repo "$PROJECTS_ROOT/acme/acme" https://github.com/QuinnNei/acme.git
mkdir -p "$VAULT/wiki/projects"
BOARD="$VAULT/wiki/projects/Acme Board.md"
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
gh_can 'project create --owner QuinnNei' '4'
gh_seq 'issue list' '[]' \
  '[{"number":1,"state":"OPEN","body":"was ACM-1\nx"},{"number":2,"state":"OPEN","body":"was ACM-2"},{"number":3,"state":"OPEN","body":"was ACM-4"},{"number":4,"state":"CLOSED","body":"was ACM-5"},{"number":5,"state":"OPEN","body":"was ACM-6"},{"number":9,"state":"OPEN","body":"Hand-made, no was line"}]'
gh_seq 'issue create' https://github.com/QuinnNei/acme/issues/1 https://github.com/QuinnNei/acme/issues/2 \
  https://github.com/QuinnNei/acme/issues/3 https://github.com/QuinnNei/acme/issues/4 https://github.com/QuinnNei/acme/issues/5
gh_can 'project item-list 4 --owner QuinnNei -L 200 --format json' '{"items":[{"id":"I2","status":"Todo","labels":[],"content":{"type":"Issue","number":2,"title":"x"}}]}'
gh_can 'project view 4 --owner QuinnNei --format json' '{"id":"PVT_1"}'
gh_can 'project field-list 4 --owner QuinnNei -L 200 --format json' '{"fields":[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]}]}'
gh_can 'issue view 1 --repo QuinnNei/acme --json id' '{"id":"ID1"}'
gh_can 'issue view 2 --repo QuinnNei/acme --json id' '{"id":"ID2"}'
gh_can 'issue view 1 --repo QuinnNei/acme --json number,title,body,labels,comments,state' '{"number":1,"title":"x","body":"","state":"OPEN","labels":[],"comments":[]}'
gh_can 'issue view 2 --repo QuinnNei/acme --json number,title,body,labels,comments,state' '{"number":2,"title":"x","body":"","state":"OPEN","labels":[],"comments":[]}'
gh_can 'api graphql -F owner=QuinnNei -F name=acme -F number=2' '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
gh_seq 'api graphql -F owner=QuinnNei -F name=acme -F number=1' \
  '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}' \
  '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":2,"state":"OPEN","repository":{"nameWithOwner":"QuinnNei/acme"}}]}}}}}'

cd "$PROJECTS_ROOT/acme/acme" || exit 1
bash "$SK" "$BOARD" "$PROJECTS_ROOT/acme/acme" --owner QuinnNei >"$FIX/out" 2>"$FIX/err"; log=$(gh_calls)
creates=$(grep '^issue create' <<<"$log")
flat=$(tr '\n' '~' <<<"$log")   # bodies span lines
expect "board made first" "$(sed -n 1p <<<"$log")" "project list --owner QuinnNei -L 200 --format json"
expect "the board gets the cards' key" "$log" "project create --owner QuinnNei --title acme (ACM) --format json --jq .number"
expect "the board is linked to the code repo" "$log" "project link 4 --owner QuinnNei --repo QuinnNei/acme"
expect "settings: the Project" "$(cat "$PROJECTS_ROOT/acme/acme/.claude/project.md")" "project: 4"
expect "settings: the cards' key" "$(cat "$PROJECTS_ROOT/acme/acme/.claude/project.md")" "key: ACM"
expect "one issue per card" "$(wc -l <<<"$creates" | tr -d ' ')" "5"
expect "lowest card number first, body starts with the was line" "$(sed -n 1p <<<"$creates" | cut -c1-85)" "issue create --repo QuinnNei/acme --title First, to do --body was ACM-1"
expect "highest card number last" "$(sed -n 5p <<<"$creates" | cut -c1-64)" "issue create --repo QuinnNei/acme --title Sixth, frontier --body"
grep -q -- 'title First, to do --body was ACM-1~.* --label grilling --label bug~' <<<"$flat" \
  && pass "tags become labels" || fail "tags become labels"
grep -q -- '--title Fourth, linked --body was ACM-4' <<<"$creates" \
  && pass "wiki-link card: title without brackets and id" || fail "wiki-link card: title without brackets and id"
grep -q -- '--title Sixth, frontier .*--label Frontier$' <<<"$creates" \
  && pass "other column: column name as label" || fail "other column: column name as label"
expect "column label is created" "$log" "label create Frontier --repo QuinnNei/acme --force"
expect "a label is made once" "$(grep -c '^label create bug --repo' <<<"$log")" "2"   # once by board.sh, once by the migration
grep -q 'was ACM-1~Goal: do the first thing.~Needs: ACM-2, OTH-9~' <<<"$flat" && pass "Needs line stays in the body" || fail "Needs line stays in the body"
grep -q 'Branch `feature/ACM-1` --label' <<<"$flat" && pass "Branch line stays as text" || fail "Branch line stays as text"
grep -q 'was ACM-5~Goal: shipped.~PR https://github.com/o/acme/pull/4 --label bug~' <<<"$flat" && pass "PR line stays as text" || fail "PR line stays as text"
expect "In progress sets the Status" "$log" "project item-edit --id I2 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
expect "Done closes the issue" "$log" "issue close 4 --repo QuinnNei/acme --comment Done on the vault board (was ACM-5)."
expect "Done closes the linked card too" "$log" "issue close 3 --repo QuinnNei/acme --comment Done on the vault board (was ACM-4)."
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
expect "rerun: no second board" "$(grep -c '^project create' <<<"$log")" "0"
expect "rerun: no blocked-by added twice" "$(grep -c 'issueId=' <<<"$log")" "0"
expect "rerun: finishes the open Done issue" "$(grep '^issue close' <<<"$log")" "issue close 3 --repo QuinnNei/acme --comment Done on the vault board (was ACM-4)."
expect "rerun: reports the cards kept" "$(grep -c '^kept' "$FIX/out2")" "5"
expect "rerun: a kept In progress card still at Todo gets its Status" "$log" "project item-edit --id I2 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
[ -f "$VAULT/Archive/Acme Board.md" ] && pass "rerun: archived again" || fail "rerun: archived again"

# Rerun after the card moved on to Done on the Project: its Status is not pushed back
rm "$VAULT/Archive/Acme Board.md"; cp "$FIX/board.copy" "$BOARD"; : > "$GH_LOG"
itemkey=$(grep -lx 'project item-list 4 --owner QuinnNei -L 200 --format json' "$GH_DIR"/*.key)
printf '%s\n' '{"items":[{"id":"I2","status":"Done","labels":[],"content":{"type":"Issue","number":2,"title":"x"}}]}' > "${itemkey%.key}.json"
bash "$SK" "$BOARD" "$PROJECTS_ROOT/acme/acme" --owner QuinnNei >/dev/null 2>&1; log=$(gh_calls)
expect "rerun: a kept card already Done keeps its Status" "$(grep -c '^project item-edit' <<<"$log")" "0"

# --key wins over the cards' key; cards under several keys give the board none
one_card() { mkdir -p "$(dirname "$1")"; printf -- '## To do\n\n- [ ] **%s-1 · One**\n- [ ] **%s-2 · Two**\n' "$2" "$3" > "$1"; }
fixture_repo "$PROJECTS_ROOT/beta" https://github.com/QuinnNei/beta.git
one_card "$VAULT/wiki/projects/Beta Board.md" OLD OLD
: > "$GH_LOG"
bash "$SK" "$VAULT/wiki/projects/Beta Board.md" "$PROJECTS_ROOT/beta" --key NEW >/dev/null 2>&1
expect "--key names the board" "$(gh_calls)" "project create --owner QuinnNei --title beta (NEW) --format json --jq .number"
fixture_repo "$PROJECTS_ROOT/gamma" https://github.com/QuinnNei/gamma.git
one_card "$VAULT/wiki/projects/Gamma Board.md" AAA BBB
: > "$GH_LOG"
bash "$SK" "$VAULT/wiki/projects/Gamma Board.md" "$PROJECTS_ROOT/gamma" >/dev/null 2>&1
expect "cards under two keys: board without a key" "$(gh_calls)" "project create --owner QuinnNei --title gamma --format json --jq .number"
done_testing
