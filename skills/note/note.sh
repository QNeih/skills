#!/usr/bin/env bash
# Appends the note text (stdin) to <vault>/Briefing notes.md as `- [ ] <date> <text>`,
# plus ` [[<project>]]` when the lookup finds a project for the current folder. Prints the line.
# Env: VAULT, PROJECTS_ROOT (as for project.sh).
set -u
text=$(tr '\n' ' ' | sed 's/^ *//; s/ *$//')
[ -n "$text" ] || { echo "error: empty note text"; exit 1; }
[ -d "${VAULT:-}" ] || { echo "error: vault ${VAULT:-} not found"; exit 1; }
project=$(bash "$(dirname "$0")/project.sh" | sed -n 's/^project: //p')
line="- [ ] $(date +%F) $text"
[ "$project" = none ] || line="$line [[$project]]"
file="$VAULT/Briefing notes.md"
# Obsidian often saves without a final newline
[ -s "$file" ] && [ -n "$(tail -c1 "$file")" ] && echo >> "$file"
echo "$line" >> "$file"
echo "$line"
