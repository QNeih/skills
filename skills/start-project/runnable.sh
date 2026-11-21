#!/usr/bin/env bash
# Says whether a project folder has something to run.
#   runnable.sh <dir>   exit 0: something to run, 1: nothing, 2: error (missing folder, unreadable run file)
# Prints the run file when it has entries, else one line per source to suggest entries from:
#   run file: .claude/launch.json (<n> entries)
#   suggest from: <path>            a compose file
#   suggest from: <path> (<script>) a package.json with a dev or start script
#   nothing to run
# Compose files and package.json count in <dir> and its direct subfolders.
set -u
[ -n "${1:-}" ] || { echo "error: no folder given"; exit 2; }
dir=$(cd "$1" 2>/dev/null && pwd -P) || { echo "error: folder $1 not found"; exit 2; }

found=0
run="$dir/.claude/launch.json"
if [ -f "$run" ]; then
  n=$(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])).get("configurations") or []; print(len(c))' "$run" 2>/dev/null) \
    || { echo "error: $run is unreadable or not valid JSON"; exit 2; }
  [ "$n" -gt 0 ] && { echo "run file: .claude/launch.json ($n entries)"; exit 0; }
fi

for d in "$dir" "$dir"/*/; do
  d=${d%/}
  [ -d "$d" ] || continue
  [ "${d##*/}" = node_modules ] && continue
  rel=${d#"$dir"}; rel=${rel#/}; rel=${rel:+$rel/}
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$d/$f" ] && { echo "suggest from: $rel$f"; found=1; }
  done
  if [ -f "$d/package.json" ]; then
    script=$(python3 -I -c '
import json,sys
s=(json.load(open(sys.argv[1])).get("scripts") or {})
print(next((k for k in ("dev","start") if k in s),""))' "$d/package.json" 2>/dev/null)
    [ -n "$script" ] && { echo "suggest from: ${rel}package.json ($script)"; found=1; }
  fi
done

[ $found -eq 1 ] && exit 0
echo "nothing to run"
exit 1
