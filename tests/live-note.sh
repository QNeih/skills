#!/usr/bin/env bash
# /note through claude -p: line appended to <vault>/Briefing notes.md, with the project link inside a project.
. "$(dirname "$0")/lib.sh"
fixture_new
fixture_note Acme
fixture_repo "$PROJECTS_ROOT/acme"
fixture_claude_md "$PROJECTS_ROOT/acme"
install_skill "$REPO_DIR/skills/note" note "$PROJECTS_ROOT/acme"
NOTES="$VAULT/Briefing notes.md"
today=$(date +%F)
export CLAUDE_MODEL=${CLAUDE_MODEL:-haiku} ALLOWED_TOOLS="Skill,Bash(VAULT=*),Bash(bash *)"

# Inside a project, file missing → created, line ends with the project link
run_claude "$PROJECTS_ROOT/acme" "/t-note call the tax office"
expect "inside project: line with link" "$(cat "$NOTES" 2>&1)" "- [ ] $today call the tax office [[Acme]]"

# Outside a project, file saved without a final newline → appended on its own line, no link
mkdir -p "$FIX/elsewhere"; fixture_claude_md "$FIX/elsewhere"
install_skill "$REPO_DIR/skills/note" note "$FIX/elsewhere"
printf -- '- [ ] 2026-01-02 older note' > "$NOTES"
run_claude "$FIX/elsewhere" "/t-note buy stamps"
expect "outside project: earlier line kept" "$(cat "$NOTES")" "- [ ] 2026-01-02 older note"
expect "outside project: line without link" "$(cat "$NOTES")" "- [ ] $today buy stamps"

# Empty text → asks for it, writes nothing
rm "$NOTES"
run_claude "$PROJECTS_ROOT/acme" "/t-note"
[ ! -e "$NOTES" ] && pass "empty text: nothing written" || fail "empty text: nothing written: $(cat "$NOTES")"
grep -q '?' <<<"$CLAUDE_OUT" && pass "empty text: asks" || fail "empty text: asks: $CLAUDE_OUT"

done_testing
