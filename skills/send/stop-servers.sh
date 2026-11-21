#!/usr/bin/env bash
# Stops every process that listens on a TCP port and whose working directory is inside a ticket worktree,
# then brings down the compose project of each run file entry that starts Docker.
#   stop-servers.sh <worktree>   prints `stopped: pid <pid>, port <ports>: <command>` per process
#                                and `stopped: compose <folder>: <command>` per compose project
#                                (`skipped: compose v1 entry <name>: …` for a docker-compose entry)
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
# `down` runs only for the project whose config files include the entry's compose file
# and all lie inside the worktree. No docker or no daemon → skipped silently.
python3 -I - "$wt" <<'PY' || rc=1
import json, os, shutil, subprocess, sys

wt = sys.argv[1]
run_file = os.path.join(wt, ".claude", "launch.json")
DEFAULT_FILES = ("compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml")

def run(cmd, folder):
    return subprocess.run(cmd, cwd=folder, capture_output=True, text=True)

def last_line(text):
    return (text.strip().splitlines() or [""])[-1]

def compose_files(pre_args, folder):
    """The entry's compose files: its -f/--file paths, else the folder's default file."""
    paths, it = [], iter(pre_args)
    for a in it:
        if a in ("-f", "--file"):
            paths.append(next(it, ""))
        elif a.startswith("--file="):
            paths.append(a.split("=", 1)[1])
    if not paths:
        paths = [next((n for n in DEFAULT_FILES if os.path.exists(os.path.join(folder, n))), DEFAULT_FILES[0])]
    return {os.path.realpath(os.path.join(folder, p)) for p in paths if p}

def inside(path):
    return os.path.realpath(path).startswith(wt + "/")

if not os.path.exists(run_file):
    sys.exit(0)
try:
    with open(run_file) as f:
        entries = json.load(f).get("configurations") or []
except (OSError, ValueError, AttributeError) as err:
    print(f"error: {run_file} unreadable: {err}")
    sys.exit(1)

rc = 0
daemon_up = {}
for e in entries:
    if not isinstance(e, dict):
        continue
    exe = e.get("runtimeExecutable") or ""
    kind = os.path.basename(exe)
    args = list(e.get("runtimeArgs") or [])
    if kind not in ("docker", "docker-compose") or "up" not in args or not shutil.which(exe):
        continue
    if kind == "docker-compose":
        # v1 has no `ls`, so whose project it is cannot be checked
        print(f"skipped: compose v1 entry {e.get('name', '?')}: bring it down by hand")
        continue
    if exe not in daemon_up:
        daemon_up[exe] = run([exe, "info"], wt).returncode == 0
    if not daemon_up[exe]:  # no daemon: nothing can be running
        continue
    base = [exe, *args[:args.index("up")]]
    folder = os.path.realpath(os.path.join(wt, e.get("cwd", "")))
    ls = run([*base, "ls", "--all", "--format", "json"], folder)
    try:
        if ls.returncode != 0:
            raise ValueError(last_line(ls.stderr))
        projects = json.loads(ls.stdout)
        if not isinstance(projects, list):
            raise ValueError("not a JSON array")
    except ValueError as err:
        print(f"error: compose {folder}: {' '.join(base[1:])} ls failed: {err}")
        rc = 1
        continue
    mine = compose_files(base[1:], folder)
    config_files = [[os.path.realpath(f) for f in (p.get("ConfigFiles") or "").split(",") if f]
                    for p in projects if isinstance(p, dict)]
    matches = [fs for fs in config_files if mine & set(fs)]
    if not matches or not all(inside(f) for fs in matches for f in fs):
        continue
    cmd = " ".join([kind, *base[1:], "down"])
    down = run([*base, "down"], folder)
    if down.returncode == 0:
        print(f"stopped: compose {folder}: {cmd}")
    else:
        print(f"error: compose {folder}: {cmd} failed: {last_line(down.stderr)}")
        rc = 1
sys.exit(rc)
PY
exit $rc
