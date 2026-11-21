#!/usr/bin/env bash
# start-project: runnable.sh says whether a folder has something to run; start.py starts the run file's
# entries detached, keeps a port another folder holds by moving the entry, and waits for the ports.
. "$(dirname "$0")/lib.sh"
fixture_new
runnable="$REPO_DIR/skills/start-project/runnable.sh"
start="$REPO_DIR/skills/start-project/start.py"
export TMPDIR="$FIX/tmp" START_PROJECT_WAIT=10
mkdir -p "$TMPDIR"
# stop every listener the test started: each one runs from inside the fixture
cleanup() {
  for pid in $(lsof -nP -iTCP -sTCP:LISTEN -t 2>/dev/null | sort -u); do
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    case "$cwd/" in "$FIX"/*) kill "$pid" 2>/dev/null ;; esac
  done
  rm -rf "$FIX"
}
trap cleanup EXIT

free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
port_cwd() {
  local pid; pid=$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)
  [ -n "$pid" ] && lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
}
# run_file <dir> <entry json>...: <dir>/.claude/launch.json with the entries
run_file() {
  local dir=$1; shift
  mkdir -p "$dir/.claude"
  { echo '{'; echo '  "version": "0.0.1",'; echo '  "configurations": ['
    local sep=
    for e in "$@"; do printf '%s    %s' "$sep" "$e"; sep=$',\n'; done
    printf '\n  ]\n}\n'; } > "$dir/.claude/launch.json"
}
# server entry: python's http.server on <port>, the port also in the arguments
server() { echo "{ \"name\": \"$1\", \"runtimeExecutable\": \"python3\", \"runtimeArgs\": [\"-m\", \"http.server\", \"$2\", \"--bind\", \"127.0.0.1\"], \"port\": $2 }"; }
# a detached server listening on <port> from <dir>; returns once it listens
serve() {
  (cd "$1" && exec nohup python3 -m http.server "$2" --bind 127.0.0.1 >/dev/null 2>&1) >/dev/null 2>&1 &
  disown
  for _ in $(seq 50); do [ -n "$(port_cwd "$2")" ] && break; sleep 0.1; done
}

# --- runnable.sh ---
p="$FIX/r-launch"; run_file "$p" "$(server web 1)"
out=$(bash "$runnable" "$p"); rc=$?
[ $rc -eq 0 ] && pass "run file with entries: exit 0" || fail "run file with entries: exit 0, got $rc"
expect "run file with entries: named" "$out" "run file: .claude/launch.json (1 entries)"

p="$FIX/r-empty"; run_file "$p"
out=$(bash "$runnable" "$p"); rc=$?
[ $rc -eq 1 ] && pass "run file without entries, no source: exit 1" || fail "run file without entries, no source: exit 1, got $rc"
expect "nothing to run: said" "$out" "nothing to run"

p="$FIX/r-compose"; mkdir -p "$p/infra"; touch "$p/compose.yml" "$p/infra/docker-compose.yml"
out=$(bash "$runnable" "$p"); rc=$?
[ $rc -eq 0 ] && pass "compose file: exit 0" || fail "compose file: exit 0, got $rc"
expect "compose file in the folder" "$out" "suggest from: compose.yml"
expect "compose file in a subfolder" "$out" "suggest from: infra/docker-compose.yml"

p="$FIX/r-npm"; mkdir -p "$p/web" "$p/api" "$p/node_modules"
echo '{"scripts": {"build": "x", "start": "x", "dev": "x"}}' > "$p/web/package.json"
echo '{"scripts": {"start": "x"}}' > "$p/api/package.json"
echo '{"scripts": {"dev": "x"}}' > "$p/node_modules/package.json"
out=$(bash "$runnable" "$p"); rc=$?
[ $rc -eq 0 ] && pass "package scripts: exit 0" || fail "package scripts: exit 0, got $rc"
expect "dev script named before start" "$out" "suggest from: web/package.json (dev)"
expect "start script" "$out" "suggest from: api/package.json (start)"
! grep -q node_modules <<<"$out" && pass "node_modules skipped" || fail "node_modules skipped"

p="$FIX/r-build"; mkdir -p "$p"; echo '{"scripts": {"build": "x"}}' > "$p/package.json"
bash "$runnable" "$p" >/dev/null; rc=$?
[ $rc -eq 1 ] && pass "package.json without dev or start: exit 1" || fail "package.json without dev or start: exit 1, got $rc"

p="$FIX/r-bad"; mkdir -p "$p/.claude"; echo '{' > "$p/.claude/launch.json"
out=$(bash "$runnable" "$p"); rc=$?
[ $rc -eq 2 ] && grep -q '^error: .* is unreadable or not valid JSON' <<<"$out" && pass "broken run file: error, exit 2" || { fail "broken run file: error, exit 2, got $rc"; echo "$out"; }

out=$(bash "$runnable" "$FIX/missing"); rc=$?
[ $rc -eq 2 ] && pass "missing folder: exit 2" || fail "missing folder: exit 2, got $rc"
expect "missing folder: named" "$out" "error: folder $FIX/missing not found"

# --- start.py ---
p="$FIX/acme"; a=$(free_port); b=$(free_port); [ "$b" != "$a" ] || b=$(free_port)
run_file "$p" "$(server web "$a")" "$(server api "$b")" '{ "name": "worker", "runtimeExecutable": "sleep", "runtimeArgs": ["300"] }'

out=$(python3 -I "$start" ports "$p"); rc=$?
expect "ports: entry to start" "$out" "start: web"
[ -z "$(port_cwd "$a")" ] && pass "ports: starts nothing" || fail "ports: starts nothing"

out=$(python3 -I "$start" up "$p"); rc=$?
[ $rc -eq 0 ] && pass "up: exit 0" || { fail "up: exit 0, got $rc"; echo "$out"; }
[ "$(grep -c '^started: ' <<<"$out")" -eq 3 ] && pass "up: every entry started" || { fail "up: every entry started"; echo "$out"; }
grep -q "^started: web pid [0-9]*, log $TMPDIR/start-project/acme-web.log$" <<<"$out" && pass "up: names pid and log" || { fail "up: names pid and log"; echo "$out"; }
expect "up: first port answers" "$out" "up: web port $a"
expect "up: second port answers" "$out" "up: api port $b"
expect "up: url of the first entry with a port" "$out" "url: http://localhost:$a"
[ "$(port_cwd "$a")" = "$p" ] && pass "up: server listens from the project folder" || fail "up: server listens from the project folder"
worker=$(sed -n 's/^started: worker pid \([0-9]*\),.*/\1/p' <<<"$out")
[ -n "$worker" ] && kill -0 "$worker" 2>/dev/null && pass "up: entry without a port keeps running" || fail "up: entry without a port keeps running"

out=$(python3 -I "$start" up "$p"); rc=$?
expect "again: running entry named" "$out" "running: web port $a"
expect "again: running entry without a port named" "$out" "running: worker pid $worker"
! grep -q '^started: ' <<<"$out" && pass "again: nothing started twice" || { fail "again: nothing started twice"; echo "$out"; }
expect "again: url" "$out" "url: http://localhost:$a"
kill "$worker" 2>/dev/null

# A port held from another folder, or from a ticket worktree inside the project, moves
for case in other worktree; do
  p="$FIX/move-$case"; port=$(free_port)
  if [ $case = other ]; then holder="$FIX/elsewhere-$case"; else holder="$p/.claude/worktrees/ACM-1"; fi
  # the same number in a field of its own and in another entry stays
  mkdir -p "$holder"
  run_file "$p" "$(server web "$port" | sed "s/ }\$/, \"timeout\": $port }/")" "$(server api "$(free_port)" | sed "s/ }\$/, \"timeout\": $port }/")"
  cp "$p/.claude/launch.json" "$FIX/before.json"
  serve "$holder" "$port"
  out=$(python3 -I "$start" up "$p"); rc=$?
  new=$(sed -n "s/^moved: web port $port -> \([0-9]*\)$/\1/p" <<<"$out")
  [ -n "$new" ] && pass "$case: entry moved to a free port" || { fail "$case: entry moved to a free port"; echo "$out"; continue; }
  expect "$case: url on the new port" "$out" "url: http://localhost:$new"
  [ "$(port_cwd "$port")" = "$holder" ] && pass "$case: the other server keeps its port" || fail "$case: the other server keeps its port"
  [ "$(port_cwd "$new")" = "$p" ] && pass "$case: ours listens on the new port" || fail "$case: ours listens on the new port"
  want=$(sed "/\"name\": \"web\"/ { s/\"$port\"/\"$new\"/; s/\"port\": $port/\"port\": $new/; }" "$FIX/before.json")
  [ "$want" = "$(cat "$p/.claude/launch.json")" ] \
    && pass "$case: only the entry's port and arguments changed" || { fail "$case: only the entry's port and arguments changed"; diff <(echo "$want") "$p/.claude/launch.json"; }
done

# A server that never listens: no answer, its log's tail, no url
p="$FIX/broken"; port=$(free_port)
run_file "$p" "{ \"name\": \"web\", \"runtimeExecutable\": \"python3\", \"runtimeArgs\": [\"-c\", \"print('boom')\"], \"port\": $port }"
out=$(START_PROJECT_WAIT=1 python3 -I "$start" up "$p"); rc=$?
[ $rc -eq 1 ] && pass "no answer: exit 1" || fail "no answer: exit 1, got $rc"
expect "no answer: named" "$out" "no answer: web port $port after 1 s"
expect "no answer: log tail shown" "$out" "  boom"
! grep -q '^url:' <<<"$out" && pass "no answer: no url" || fail "no answer: no url"

p="$FIX/nocmd"; run_file "$p" '{ "name": "web", "runtimeExecutable": "no-such-command-xyz", "port": 1 }'
out=$(START_PROJECT_WAIT=0 python3 -I "$start" up "$p"); rc=$?
[ $rc -eq 1 ] && grep -q "^error: web: cannot run 'no-such-command-xyz'" <<<"$out" && pass "missing command: error" || { fail "missing command: error"; echo "$out"; }

# A container entry whose port another program holds is reported, not started or moved (no docker here)
p="$FIX/containers"; port=$(free_port); mkdir -p "$FIX/elsewhere-docker"
run_file "$p" "{ \"name\": \"containers\", \"runtimeExecutable\": \"docker\", \"runtimeArgs\": [\"compose\", \"up\"], \"port\": $port }"
serve "$FIX/elsewhere-docker" "$port"
out=$(python3 -I "$start" up "$p"); rc=$?
grep -q "^taken: containers port $port: .*http.server" <<<"$out" && pass "container port taken: named" || { fail "container port taken: named"; echo "$out"; }
! grep -q '^\(started\|moved\|no answer\):' <<<"$out" && pass "container port taken: nothing started, moved or awaited" || { fail "container port taken: nothing started, moved or awaited"; echo "$out"; }
grep -q "\"port\": $port" "$p/.claude/launch.json" && pass "container port taken: run file unchanged" || fail "container port taken: run file unchanged"

# A stand-in docker: `compose ... ps --format json` prints $DOCKER_PS, every call is logged
mkdir -p "$FIX/dockerbin"
cat > "$FIX/dockerbin/docker" <<'SH'
#!/usr/bin/env bash
echo "$PWD: $*" >> "$FIX/docker.log"
case " $* " in *" ps "*) cat "$DOCKER_PS" 2>/dev/null ;; esac
SH
chmod +x "$FIX/dockerbin/docker"
export FIX DOCKER_PS="$FIX/docker-ps.json"
p="$FIX/compose"; port=$(free_port); mkdir -p "$p/infra"
run_file "$p" "{ \"name\": \"containers\", \"runtimeExecutable\": \"docker\", \"runtimeArgs\": [\"compose\", \"-f\", \"infra/c.yml\", \"up\", \"--build\"], \"port\": $port }"
serve "$FIX/elsewhere-docker" "$port"
echo "{\"Name\": \"web\", \"Publishers\": [{\"TargetPort\": 80, \"PublishedPort\": $port}]}" > "$DOCKER_PS"
out=$(PATH="$FIX/dockerbin:$PATH" python3 -I "$start" up "$p"); rc=$?
expect "compose publishes the port: running" "$out" "running: containers port $port"
expect "compose publishes the port: url" "$out" "url: http://localhost:$port"
grep -qxF "$p: compose -f infra/c.yml ps --format json" "$FIX/docker.log" && pass "compose asked with the entry's compose file, from its folder" || { fail "compose asked with the entry's compose file, from its folder"; cat "$FIX/docker.log"; }
! grep -q " up" "$FIX/docker.log" && pass "compose publishes the port: not started" || fail "compose publishes the port: not started"
echo '[{"Name": "db", "Publishers": [{"TargetPort": 5432, "PublishedPort": 5432}]}]' > "$DOCKER_PS"
out=$(PATH="$FIX/dockerbin:$PATH" python3 -I "$start" up "$p"); rc=$?
grep -q "^taken: containers port $port: " <<<"$out" && pass "another project's container port: taken" || { fail "another project's container port: taken"; echo "$out"; }
! grep -q '^url:' <<<"$out" && pass "another project's container port: no url" || fail "another project's container port: no url"

# wait alone: for a server started some other way (an App session's preview_start)
p="$FIX/app"; port=$(free_port); run_file "$p" "$(server web "$port")"
serve "$p" "$port"
out=$(python3 -I "$start" wait "$p"); rc=$?
[ $rc -eq 0 ] && pass "wait: exit 0" || fail "wait: exit 0, got $rc"
expect "wait: url" "$out" "url: http://localhost:$port"

py=$(python3 -I -c 'import sys; print(sys.executable)'); mkdir -p "$FIX/nolsof"
out=$(PATH="$FIX/nolsof" "$py" -I "$start" ports "$FIX/app"); rc=$?
[ $rc -eq 1 ] && pass "no lsof: exit 1" || fail "no lsof: exit 1, got $rc"
expect "no lsof: named" "$out" "error: lsof not installed"

out=$(python3 -I "$start" up "$FIX/r-npm"); rc=$?
[ $rc -eq 1 ] && pass "no run file: exit 1" || fail "no run file: exit 1, got $rc"
expect "no run file: named" "$out" "error: no run file: $FIX/r-npm/.claude/launch.json"
done_testing
