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

# --- Compose projects. A stand-in docker logs each call as `<cwd>: <args>`;
# `ps` prints $DOCKER_PS, `ls` prints $DOCKER_LS, a call naming a subcommand in $DOCKER_FAIL exits 1.
mkdir -p "$FIX/dockerbin" "$wt/docker" "$checkout/docker" "$wt/.claude"
cat > "$FIX/dockerbin/docker" <<'SH'
#!/usr/bin/env bash
echo "$PWD: $*" >> "$DOCKER_LOG"
for a in "$@"; do case " ${DOCKER_FAIL:-} " in *" $a "*) echo "cannot $a" >&2; exit 1 ;; esac; done
for a in "$@"; do
  case $a in ps) cat "$DOCKER_PS"; exit 0 ;; ls) cat "$DOCKER_LS"; exit 0 ;; esac
done
SH
chmod +x "$FIX/dockerbin/docker"
export DOCKER_LOG="$FIX/docker.log" DOCKER_PS="$FIX/docker-ps.json" DOCKER_LS="$FIX/docker-ls.json"
cat > "$wt/.claude/launch.json" <<'JSON'
{ "version": "0.0.1", "configurations": [
  { "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "port": 3000 },
  { "name": "db", "runtimeExecutable": "docker", "runtimeArgs": ["compose", "-f", "c.yml", "up", "--build"], "cwd": "docker", "port": 5432 }
] }
JSON
running() { echo '{"Project":"docker","Service":"db"}' > "$DOCKER_PS"; echo "[{\"Name\":\"docker\",\"Status\":\"running(1)\",\"ConfigFiles\":\"$1/docker/c.yml\"}]" > "$DOCKER_LS"; }
dstop() { : > "$DOCKER_LOG"; PATH="$FIX/dockerbin:$PATH" bash "$stop" "$wt"; }

running "$wt"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && pass "compose: exit 0" || fail "compose: exit 0, got $rc"
grep -qxF "$wt/docker: compose -f c.yml down" "$DOCKER_LOG" && pass "compose: down with the entry's args before up, in its folder" || { fail "compose: down with the entry's args before up, in its folder"; cat "$DOCKER_LOG"; }
expect "compose: one stopped line" "$out" "stopped: compose $wt/docker: docker compose -f c.yml down"

running "$checkout"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && pass "main checkout's project: exit 0" || fail "main checkout's project: exit 0, got $rc"
! grep -q " down$" "$DOCKER_LOG" && pass "main checkout's project of the same name: no down" || { fail "main checkout's project of the same name: no down"; cat "$DOCKER_LOG"; }
! grep -q "^stopped: " <<<"$out" && pass "main checkout's project: nothing reported stopped" || { fail "main checkout's project: nothing reported stopped"; echo "$out"; }

running "$wt"; : > "$DOCKER_PS"
out=$(dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ! grep -q " down$" "$DOCKER_LOG" && pass "no containers: no down, no output" || { fail "no containers: no down, no output"; echo "$out"; cat "$DOCKER_LOG"; }

running "$wt"
out=$(DOCKER_FAIL=ps dstop); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ! grep -q " down$" "$DOCKER_LOG" && pass "daemon not running: skipped, exit 0" || { fail "daemon not running: skipped, exit 0 (rc $rc)"; echo "$out"; }

out=$(DOCKER_FAIL=down dstop); rc=$?
[ $rc -eq 1 ] && pass "down fails: exit 1" || fail "down fails: exit 1, got $rc"
grep -q "^error: compose $wt/docker: docker compose -f c.yml down failed" <<<"$out" && pass "down fails: error line" || { fail "down fails: error line"; echo "$out"; }

# Docker not installed: PATH holds only the tools the script needs, so no docker can be found
mkdir -p "$FIX/minbin"
for t in lsof ps sort sed paste tr cut sleep python3; do ln -s "$(command -v $t)" "$FIX/minbin/$t"; done
out=$(PATH="$FIX/minbin" "$BASH" "$stop" "$wt"); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "docker not installed: skipped, exit 0" || { fail "docker not installed: skipped, exit 0 (rc $rc)"; echo "$out"; }
done_testing
