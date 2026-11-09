#!/usr/bin/env bash
# Adds a Fork workspace NAME with FOLDER as its only tab to Fork's session.json.
# Run only while Fork is quit (Fork rewrites the file while it runs).
#   fork.sh SESSION_JSON NAME FOLDER
# Prints `added: NAME`, `exists: NAME`, or `error: ...` (exit 1, file untouched).
set -eu
file=$1 name=$2 folder=$3

# A workspace to copy the shape from: the first one with a window that has tabs
tpl='first(.workspaces[]? | select((.tabs | type) == "array" and (.windows | type) == "array"
  and any(.windows[]; (.tabs | type) == "array" and length > 0)))'
if ! jq -e '.workspaces | type == "array"' "$file" >/dev/null 2>&1; then
  echo "error: unexpected format: no workspaces list in $file"; exit 1
fi
if jq -e --arg n "$name" 'any(.workspaces[]; .name == $n)' "$file" >/dev/null; then
  echo "exists: $name"; exit 0
fi
if ! jq -e "$tpl" "$file" >/dev/null; then
  echo "error: unexpected format: no workspace with an open tab to copy the shape from"; exit 1
fi

cp "$file" "$file.bak"
jq --arg n "$name" --arg f "$folder" --arg id "$(uuidgen | tr a-f A-F)" "
  .workspaces += [$tpl
    | .id = \$id | .name = \$n | .tabs = [\$f] | .activeTabIndex = 0
    | .windows = [.windows[0] | .tabs = [\$f] | .activeTabIndex = 0]]" "$file.bak" > "$file.tmp"
mv "$file.tmp" "$file"
echo "added: $name"
