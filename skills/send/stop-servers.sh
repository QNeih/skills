#!/usr/bin/env bash
# Stops every process that listens on a TCP port and whose working directory is inside a ticket worktree.
#   stop-servers.sh <worktree>   prints `stopped: pid <pid>, port <ports>: <command>` per process
# Takes only <checkout>/.claude/worktrees/<id>: a listener in a main checkout may be a server Quinn runs.
set -u
wt=$(cd "${1:-}" 2>/dev/null && pwd -P) || { echo "error: worktree ${1:-(none given)} not found"; exit 1; }
case "$wt" in
  */.claude/worktrees/*) ;;
  *) echo "error: $wt is not a ticket worktree (<checkout>/.claude/worktrees/<id>)"; exit 1 ;;
esac
command -v lsof >/dev/null || { echo "error: lsof not installed"; exit 1; }

# a killed child stays a zombie until its parent reaps it; that counts as stopped
alive() { kill -0 "$1" 2>/dev/null && [ "$(ps -o stat= -p "$1" 2>/dev/null | cut -c1)" != Z ]; }

rc=0
for pid in $(lsof -nP -iTCP -sTCP:LISTEN -t 2>/dev/null | sort -u); do
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd/" in "$wt"/*) ;; *) continue ;; esac
  ports=$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN -Fn 2>/dev/null | sed -n 's/^n.*:\([0-9]*\)$/\1/p' | sort -un | paste -sd, -)
  cmd=$(ps -ww -o command= -p "$pid")
  kill "$pid" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do alive "$pid" || break; sleep 0.2; done
  if alive "$pid"; then echo "error: pid $pid (port $ports) did not stop: $cmd"; rc=1
  else echo "stopped: pid $pid, port $ports: $cmd"; fi
done
exit $rc
