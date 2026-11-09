#!/usr/bin/env bash
# fork.sh adds a Fork workspace to a copy of session.json (never the real one).
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/new-project"
fixture_new
S="$FIX/session.json"
cat > "$S" <<'JSON'
{"activeWorkspaceIndex":1,"windows":[{"workspaceId":"A1","isFullScreen":false}],"activeWindowIndex":0,
 "workspaces":[
  {"id":"A0","name":"Empty","tabs":[],"windows":[],"activeWindowIndex":-1,"activeTabIndex":0},
  {"id":"A1","name":"Acme","tabs":["/p/acme","/p/other"],"activeTabIndex":1,"activeWindowIndex":0,
   "windows":[{"tabs":["/p/acme","/p/other"],"activeTabIndex":1,"isFullScreen":false,"frame":{"x":0,"y":0,"width":800,"height":600}}]}]}
JSON
before=$(cat "$S")

out=$(bash "$SK/fork.sh" "$S" "Beta Shop" "/p/beta")
expect "add: prints the workspace" "$out" "added: Beta Shop"
w=$(jq -c '.workspaces[] | select(.name == "Beta Shop")' "$S")
expect "add: folder is the only tab" "$(jq -c .tabs <<<"$w")" '["/p/beta"]'
expect "add: window shaped like an existing one, folder its only tab" "$(jq -c '.windows' <<<"$w")" \
  '[{"tabs":["/p/beta"],"activeTabIndex":0,"isFullScreen":false,"frame":{"x":0,"y":0,"width":800,"height":600}}]'
expect "add: other fields copied" "$(jq -c '[.activeTabIndex, .activeWindowIndex]' <<<"$w")" '[0,0]'
id=$(jq -r .id <<<"$w")
[[ $id =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]] && pass "add: new UUID" || fail "add: new UUID ($id)"
expect "add: existing workspaces kept" "$(jq -r '.workspaces[].name' "$S")" "Acme"
expect "add: top level untouched" "$(jq -c '.windows' "$S")" '[{"workspaceId":"A1","isFullScreen":false}]'
[ "$(cat "$S.bak")" = "$before" ] && pass "add: backup of the old file" || fail "add: backup of the old file"

# re-run: the workspace exists, nothing changes
after=$(cat "$S")
expect "re-run: says it exists" "$(bash "$SK/fork.sh" "$S" "Beta Shop" "/p/beta")" "exists: Beta Shop"
[ "$(cat "$S")" = "$after" ] && pass "re-run: file unchanged" || fail "re-run: file unchanged"

# unexpected format: error, file untouched, no backup
for json in '{"windows":[]}' '{"workspaces":{}}' '{"workspaces":[{"id":"A0","name":"Empty","tabs":[],"windows":[]}]}' 'not json'; do
  printf '%s' "$json" > "$FIX/odd.json"
  out=$(bash "$SK/fork.sh" "$FIX/odd.json" "Beta" "/p/beta") && rc=0 || rc=$?
  { [ $rc -eq 1 ] && [[ $out == "error: unexpected format"* ]] && [ "$(cat "$FIX/odd.json")" = "$json" ] && [ ! -e "$FIX/odd.json.bak" ]; } \
    && pass "odd format stops untouched: $json" || fail "odd format stops untouched: $json ($rc: $out)"
done

done_testing
