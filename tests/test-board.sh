#!/usr/bin/env bash
# Board step file parts: board.sh creates a vault board and saves a board override,
# checked through the project lookup.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/ticket"
fixture_new
lookup() { (cd "$1" && bash "$SK/project.sh"); }
colors='{"kanban-plugin":"board","tag-colors":[{"tagKey":"#urgent","color":"#ffffff","backgroundColor":"#e03131"}]}'

# Another board without tag colours, one with them
fixture_note Beta
printf -- '---\n\nkanban-plugin: board\n\n---\n\n## To do\n\n' > "$VAULT/Projects/Beta/Beta Board.md"
fixture_note Gamma
printf -- '## To do\n\n\n%%%% kanban:settings\n```\n%s\n```\n%%%%\n' "$colors" > "$VAULT/Projects/Gamma/Gamma Board.md"

# obsidian: board created, lookup now finds a vault board
fixture_note Acme
mkdir -p "$PROJECTS_ROOT/acme"
out=$(bash "$SK/board.sh" create "$VAULT/Projects/Acme/Acme.md")
expect "create: prints the board file" "$out" "created: $VAULT/Projects/Acme/Acme Board.md"
expect "create: lookup sees a vault board" "$(lookup "$PROJECTS_ROOT/acme")" "board: vault"
b=$(cat "$VAULT/Projects/Acme/Acme Board.md")
expect "create: kanban board" "$b" "kanban-plugin: board"
expect "create: To do column" "$b" "## To do"
expect "create: In progress column" "$b" "## In progress"
expect "create: Done column" "$b" "## Done"
grep -qF '"tag-colors":[{"tagKey":"#urgent","color":"#ffffff","backgroundColor":"#e03131"}]' <<<"$b" \
  && pass "create: tag colours copied from the board that has them" || fail "create: tag colours copied from the board that has them"

# existing board stays untouched
echo keep > "$VAULT/Projects/Acme/Acme Board.md"
out=$(bash "$SK/board.sh" create "$VAULT/Projects/Acme/Acme.md")
expect "create: existing board reported" "$out" "exists: $VAULT/Projects/Acme/Acme Board.md"
expect "create: existing board untouched" "$(cat "$VAULT/Projects/Acme/Acme Board.md")" "keep"

# no board in the vault has tag colours → board without them
rm "$VAULT/Projects/Gamma/Gamma Board.md"
fixture_note Delta
bash "$SK/board.sh" create "$VAULT/Projects/Delta/Delta.md" >/dev/null
b=$(cat "$VAULT/Projects/Delta/Delta Board.md")
expect "create without colours: In progress column" "$b" "## In progress"
grep -q tag-colors <<<"$b" && fail "create without colours: no tag-colors" || pass "create without colours: no tag-colors"

# link or text answer → board override in the note
fixture_note Omega 'repo: https://git.acme.test/omega'
mkdir -p "$PROJECTS_ROOT/omega"
url='https://dev.azure.test/acme/omega/_boards/board'
bash "$SK/board.sh" set "$VAULT/Projects/Omega/Omega.md" "$url" >/dev/null
expect "set: lookup reads the override" "$(lookup "$PROJECTS_ROOT/omega")" "board: $url"
expect "set: other properties kept" "$(cat "$VAULT/Projects/Omega/Omega.md")" "repo: https://git.acme.test/omega"
bash "$SK/board.sh" set "$VAULT/Projects/Omega/Omega.md" 'Trello: team board #2' >/dev/null
expect "set: replaces the override" "$(lookup "$PROJECTS_ROOT/omega")" "board: Trello: team board #2"
[ "$(grep -c '^board:' "$VAULT/Projects/Omega/Omega.md")" = 1 ] && pass "set: one board line" || fail "set: one board line"
done_testing
