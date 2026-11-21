#!/usr/bin/env bash
# send/stop-servers.sh: stops the listeners inside one ticket worktree, and nothing else.
. "$(dirname "$0")/lib.sh"
fixture_new
stop="$REPO_DIR/skills/send/stop-servers.sh"
pids=
trap 'kill $pids 2>/dev/null; rm -rf "$FIX"' EXIT

# serve <dir>: a detached server listening from <dir>; prints its pid once it listens
serve() {
  local pid
  # exec: without it the waiting subshell keeps this command substitution's pipe open
  pid=$( (cd "$1" && exec nohup python3 -m http.server 0 --bind 127.0.0.1 >/dev/null 2>&1) >/dev/null 2>&1 & echo $!)
  for _ in $(seq 50); do [ -n "$(port_of "$pid")" ] && break; sleep 0.1; done
  echo "$pid"
}
port_of() { lsof -nP -a -p "$1" -iTCP -sTCP:LISTEN -Fn 2>/dev/null | sed -n 's/^n.*:\([0-9]*\)$/\1/p' | head -1; }
alive() { kill -0 "$1" 2>/dev/null; }

checkout="$PROJECTS_ROOT/acme"
wt="$checkout/.claude/worktrees/ACM-1" sibling="$checkout/.claude/worktrees/ACM-10"
mkdir -p "$wt/frontend" "$sibling"
own=$(serve "$wt"); nested=$(serve "$wt/frontend"); main=$(serve "$checkout"); other=$(serve "$sibling")
pids="$own $nested $main $other"
own_port=$(port_of "$own")
[ -n "$own_port" ] && [ -n "$(port_of "$other")" ] || { fail "fixture: servers listen"; exit 1; }

out=$(bash "$stop" "$wt"); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0: $rc"
grep -q "^stopped: pid $own, port $own_port: .*http.server" <<<"$out" && pass "names pid, port and command" || { fail "names pid, port and command"; echo "$out"; }
[ "$(grep -c '^stopped: ' <<<"$out")" -eq 2 ] && pass "one line per stopped process" || { fail "one line per stopped process"; echo "$out"; }
! alive "$own" && ! alive "$nested" && pass "listeners in the worktree and its subfolders are gone" || fail "listeners in the worktree and its subfolders are gone"
alive "$main" && pass "main checkout's listener stays" || fail "main checkout's listener stays"
alive "$other" && pass "a worktree sharing the name prefix stays" || fail "a worktree sharing the name prefix stays"

out=$(bash "$stop" "$wt"); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "nothing listening: no output, exit 0" || { fail "nothing listening: no output, exit 0"; echo "$out"; }

out=$(bash "$stop" "$checkout"); rc=$?
[ $rc -eq 1 ] && pass "main checkout: exit 1" || fail "main checkout: exit 1, got $rc"
expect "main checkout: refused" "$out" "error: $checkout is not a ticket worktree (<checkout>/.claude/worktrees/<id>)"
alive "$main" && pass "main checkout: listener untouched" || fail "main checkout: listener untouched"

# No argument, run from inside another worktree that has a listener: nothing is stopped
out=$(cd "$sibling" && bash "$stop"); rc=$?
[ $rc -eq 1 ] && pass "no argument: exit 1" || fail "no argument: exit 1, got $rc"
expect "no argument: named" "$out" "error: no worktree given"
alive "$other" && pass "no argument: the current folder's listener stays" || fail "no argument: the current folder's listener stays"

out=$(bash "$stop" "$FIX/missing"); rc=$?
[ $rc -eq 1 ] && pass "missing folder: exit 1" || fail "missing folder: exit 1, got $rc"
expect "missing folder: named" "$out" "error: worktree $FIX/missing not found"

# --- Compose projects. A stand-in docker logs each call as `<cwd>: <args>`; `ls` prints $DOCKER_LS,
# a call naming a subcommand in $DOCKER_FAIL exits 1 (`info` fails = daemon down).
mkdir -p "$FIX/dockerbin" "$wt/docker" "$checkout/docker" "$wt/.claude"
cat > "$FIX/dockerbin/docker" <<'SH'
#!/usr/bin/env bash
echo "$PWD: $*" >> "$DOCKER_LOG"
for a in "$@"; do case " ${DOCKER_FAIL:-} " in *" $a "*) echo "cannot $a" >&2; exit 1 ;; esac; done
for a in "$@"; do case $a in ls) cat "$DOCKER_LS"; exit 0 ;; esac; done
SH
chmod +x "$FIX/dockerbin/docker"
cp "$FIX/dockerbin/docker" "$FIX/dockerbin/docker-compose"
export DOCKER_LOG="$FIX/docker.log" DOCKER_LS="$FIX/docker-ls.json"
launch() { printf '{ "version": "0.0.1", "configurations": [\n  { "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "port": 3000 },\n  %s\n] }\n' "$1" > "$wt/.claude/launch.json"; }
db='{ "name": "db", "runtimeExecutable": "docker", "runtimeArgs": ["compose", "-f", "c.yml", "up", "--build"], "cwd": "docker", "port": 5432 }'
# project <config files>: `ls` lists one project with these comma-separated config files
project() { echo "[{\"Name\":\"docker\",\"Status\":\"running(1)\",\"ConfigFiles\":\"$1\"}]" > "$DOCKER_LS"; }
dstop() { : > "$DOCKER_LOG"; PATH="$FIX/dockerbin:$PATH" bash "$stop" "$wt"; }
no_down() { ! grep -q " down$" "$DOCKER_LOG"; }

launch "$db"; project "$wt/docker/c.yml"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && pass "compose: exit 0" || fail "compose: exit 0, got $rc"
grep -qxF "$wt/docker: compose -f c.yml down" "$DOCKER_LOG" && pass "compose (ls prints a JSON array): down with the entry's args before up, in its folder" || { fail "compose (ls prints a JSON array): down with the entry's args before up, in its folder"; cat "$DOCKER_LOG"; }
expect "compose: one stopped line" "$out" "stopped: compose $wt/docker: docker compose -f c.yml down"

touch "$wt/docker/compose.yml"
launch '{ "name": "db", "runtimeExecutable": "docker", "runtimeArgs": ["compose", "up"], "cwd": "docker", "port": 5432 }'
project "$wt/docker/compose.yml"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && grep -qxF "$wt/docker: compose down" "$DOCKER_LOG" && pass "no -f: the folder's default compose file is the entry's" || { fail "no -f: the folder's default compose file is the entry's"; echo "$out"; cat "$DOCKER_LOG"; }
launch "$db"

project "$checkout/docker/c.yml"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && no_down && pass "main checkout's project of the same name: no down, no output" || { fail "main checkout's project of the same name: no down, no output"; echo "$out"; cat "$DOCKER_LOG"; }

project "$wt/docker/c.yml,$checkout/docker/override.yml"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && no_down && pass "config files partly outside the worktree: skipped" || { fail "config files partly outside the worktree: skipped"; echo "$out"; cat "$DOCKER_LOG"; }

echo '[]' > "$DOCKER_LS"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && no_down && pass "no project running: no down, no output" || { fail "no project running: no down, no output"; echo "$out"; }

project "$wt/docker/c.yml"
out=$(DOCKER_FAIL=info dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && no_down && pass "daemon down: skipped silently, exit 0" || { fail "daemon down: skipped silently, exit 0 (rc $rc)"; echo "$out"; }

out=$(DOCKER_FAIL=ls dstop); rc=$?
[ $rc -eq 1 ] && no_down && pass "ls fails: exit 1, no down" || fail "ls fails: exit 1, no down (rc $rc)"
expect "ls fails: error line" "$out" "error: compose $wt/docker: compose -f c.yml ls failed: cannot ls"

echo 'not json' > "$DOCKER_LS"
out=$(dstop); rc=$?
[ $rc -eq 1 ] && grep -q "^error: compose $wt/docker: compose -f c.yml ls failed: " <<<"$out" && pass "ls prints no JSON: error line, exit 1" || { fail "ls prints no JSON: error line, exit 1 (rc $rc)"; echo "$out"; }

project "$wt/docker/c.yml"
out=$(DOCKER_FAIL=down dstop); rc=$?
[ $rc -eq 1 ] && pass "down fails: exit 1" || fail "down fails: exit 1, got $rc"
expect "down fails: error line" "$out" "error: compose $wt/docker: docker compose -f c.yml down failed: cannot down"

launch '{ "name": "legacy", "runtimeExecutable": "docker-compose", "runtimeArgs": ["up"], "cwd": "docker" }'
out=$(dstop); rc=$?
[ $rc -eq 0 ] && no_down && pass "compose v1 entry: exit 0, no down" || fail "compose v1 entry: exit 0, no down (rc $rc)"
expect "compose v1 entry: skipped line" "$out" "skipped: compose v1 entry legacy: bring it down by hand"

echo '{ "configurations": [' > "$wt/.claude/launch.json"
out=$(dstop); rc=$?
[ $rc -eq 1 ] && grep -q "^error: $wt/.claude/launch.json unreadable: " <<<"$out" && pass "malformed run file: error line, exit 1" || { fail "malformed run file: error line, exit 1 (rc $rc)"; echo "$out"; }

echo '{ "configurations": ["web", 3] }' > "$wt/.claude/launch.json"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "entries that are not objects: ignored" || { fail "entries that are not objects: ignored (rc $rc)"; echo "$out"; }

rm "$wt/.claude/launch.json"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "no run file: no output, exit 0" || { fail "no run file: no output, exit 0 (rc $rc)"; echo "$out"; }

# Docker not installed: PATH holds only the tools the script needs, so no docker can be found
launch "$db"; project "$wt/docker/c.yml"
mkdir -p "$FIX/minbin"
for t in lsof ps sort sed paste tr cut sleep python3; do ln -s "$(command -v $t)" "$FIX/minbin/$t"; done
out=$(PATH="$FIX/minbin" "$BASH" "$stop" "$wt"); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "docker not installed: skipped, exit 0" || { fail "docker not installed: skipped, exit 0 (rc $rc)"; echo "$out"; }
done_testing
