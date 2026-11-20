#!/usr/bin/env bash
# note.sh: the line it appends, tagged with the project in a flat or nested checkout and untagged outside one.
. "$(dirname "$0")/lib.sh"
NOTE="$REPO_DIR/skills/note/note.sh"
fixture_new
NOTES="$VAULT/Briefing notes.md"
today=$(date +%F)
note() { (cd "$1" && echo "$2" | bash "$NOTE" 2>&1); }

fixture_repo "$PROJECTS_ROOT/Solo"
expect "flat checkout: tagged with the folder's name" "$(note "$PROJECTS_ROOT/Solo" "call the tax office")" "- [ ] $today call the tax office [[Solo]]"
fixture_repo "$PROJECTS_ROOT/Nest/Nest"
mkdir -p "$PROJECTS_ROOT/Nest/Nest/src"
expect "nested checkout, subfolder: tagged with the project" "$(note "$PROJECTS_ROOT/Nest/Nest/src" "ship it")" "- [ ] $today ship it [[Nest]]"
mkdir -p "$FIX/elsewhere"
printf -- '- [ ] 2026-01-02 older note' > "$NOTES"
expect "outside a project: no tag" "$(note "$FIX/elsewhere" "buy stamps")" "- [ ] $today buy stamps"
expect "file without a final newline: earlier line kept" "$(cat "$NOTES")" "- [ ] 2026-01-02 older note"
expect "file without a final newline: new line on its own" "$(tail -1 "$NOTES")" "- [ ] $today buy stamps"
out=$(note "$FIX/elsewhere" ""); [ $? -ne 0 ] && expect "empty text: error line" "$out" "error: empty note text" || fail "empty text: fails"
done_testing
