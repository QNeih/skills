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
done_testing
