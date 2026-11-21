#!/usr/bin/env bash
# Stops every process that listens on a TCP port and whose working directory is inside a ticket worktree,
# then brings down the compose project of each run file entry that starts Docker.
#   stop-servers.sh <worktree>   prints `stopped: pid <pid>, port <ports>: <command>` per process
#                                and `stopped: compose <folder>: <command>` per compose project
# Takes only <checkout>/.claude/worktrees/<id>: a listener in a main checkout may be a server Quinn runs.
set -u
[ -n "${1:-}" ] || { echo "error: no worktree given"; exit 1; }
wt=$(cd "$1" 2>/dev/null && pwd -P) || { echo "error: worktree $1 not found"; exit 1; }
case "$wt" in
  */.claude/worktrees/*) ;;
  *) echo "error: $wt is not a ticket worktree (<checkout>/.claude/worktrees/<id>)"; exit 1 ;;
esac
command -v lsof >/dev/null || { echo "error: lsof not installed"; exit 1; }

# a killed child stays a zombie until its parent reaps it; that counts as stopped
alive() { kill -0 "$1" 2>/dev/null && [ "$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' | cut -c1)" != Z ]; }

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

# Docker publishes container ports from its own process, so the loop above misses containers.
# Compose names a project after its folder, so a main checkout's project can share the name:
# `down` runs only when every config file of the project lies inside the worktree.
python3 -I - "$wt" <<'PY' || rc=1
import json, os, shutil, subprocess, sys

wt = sys.argv[1]
try:
    with open(os.path.join(wt, ".claude", "launch.json")) as f:
        entries = json.load(f).get("configurations") or []
except (OSError, ValueError):
    sys.exit(0)

def rows(out):
    out = out.strip()
    try:
        data = json.loads(out) if out.startswith("[") else [json.loads(l) for l in out.splitlines() if l.strip()]
    except ValueError:
        return []
    return [r for r in data if isinstance(r, dict)]

def inside(path):
    return os.path.realpath(path).startswith(wt + "/")

rc = 0
for e in entries:
    exe = e.get("runtimeExecutable", "")
    if os.path.basename(exe) not in ("docker", "docker-compose") or not shutil.which(exe):
        continue
    args = list(e.get("runtimeArgs") or [])
    if "up" not in args:
        continue
    base = [exe, *args[:args.index("up")]]
    folder = os.path.realpath(os.path.join(wt, e.get("cwd", "")))
    def run(*sub):
        return subprocess.run([*base, *sub], cwd=folder, capture_output=True, text=True)
    ps = run("ps", "-a", "--format", "json")
    if ps.returncode != 0:  # daemon not running: nothing can be running
        continue
    projects = {r.get("Project") for r in rows(ps.stdout)} - {None}
    if not projects:
        continue
    ls = run("ls", "--all", "--format", "json")
    files = {r.get("Name"): (r.get("ConfigFiles") or "").split(",") for r in rows(ls.stdout)}
    if not all(files.get(p) and all(f and inside(f) for f in files[p]) for p in projects):
        continue
    cmd = " ".join([os.path.basename(exe), *base[1:], "down"])
    down = run("down")
    if down.returncode == 0:
        print(f"stopped: compose {folder}: {cmd}")
    else:
        err = (down.stderr.strip().splitlines() or [""])[-1]
        print(f"error: compose {folder}: {cmd} failed: {err}")
        rc = 1
sys.exit(rc)
PY
exit $rc
