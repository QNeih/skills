#!/usr/bin/env bash
# File parts of the board step (BOARD.md).
#   board.sh create NOTE        create "<name> Board.md" next to the project note
#   board.sh set NOTE VALUE     save VALUE as the note's `board:` override
set -eu
cmd=$1 note=$2
name=$(basename "$note" .md)

case $cmd in
create)
  file="$(dirname "$note")/$name Board.md"
  if [ -e "$file" ]; then echo "exists: $file"; exit 0; fi
  # Tag colours of the first other vault board that has them
  colors=$(cat "$(dirname "$(dirname "$note")")"/*/*" Board.md" 2>/dev/null | grep -oE -m1 '"tag-colors":\[[^]]*\]' || true)
  cat > "$file" <<MD
---

kanban-plugin: board

---

## To do



## In progress



## Done

**Complete**




%% kanban:settings
\`\`\`
{"kanban-plugin":"board"${colors:+,$colors}}
\`\`\`
%%
MD
  echo "created: $file"
  ;;
set)
  v=${3//\\/\\\\}; v=${v//\"/\\\"}
  if [ "$(head -1 "$note")" != --- ]; then printf -- '---\n---\n' | cat - "$note" > "$note.tmp" && mv "$note.tmp" "$note"; fi
  # Replace the board line in the frontmatter, else add it before the closing ---
  awk -v line="board: \"$v\"" '
    NR > 1 && !end && /^board:/ { print line; set = 1; next }
    NR > 1 && !end && $0 == "---" { if (!set) print line; end = 1 }
    { print }' "$note" > "$note.tmp" && mv "$note.tmp" "$note"
  echo "saved: board in $note"
  ;;
*) echo "usage: board.sh create NOTE | set NOTE VALUE" >&2; exit 2 ;;
esac
