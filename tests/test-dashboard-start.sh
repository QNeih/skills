#!/usr/bin/env bash
# dashboard/start.sh: runs the dashboard repo's start.sh, nested layout first, then flat, passing the arguments on.
. "$(dirname "$0")/lib.sh"
fixture_new
start="$REPO_DIR/skills/dashboard/start.sh"

# fake_start <dir>: a start.sh in <dir> that prints its own path and its arguments
fake_start() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho "ran $0 $*"\n' > "$1/start.sh"
  chmod +x "$1/start.sh"
}

out=$(bash "$start" 2>&1); rc=$?
[ $rc -eq 1 ] && pass "missing dashboard: exit 1" || fail "missing dashboard: exit 1, got $rc"
expect "missing dashboard: names both places" "$out" "error: dashboard repo not found: no start.sh in $PROJECTS_ROOT/dashboard/dashboard or $PROJECTS_ROOT/dashboard"

fake_start "$PROJECTS_ROOT/dashboard"
out=$(bash "$start" --stop 2>&1); rc=$?
[ $rc -eq 0 ] && pass "flat dashboard: exit 0" || fail "flat dashboard: exit 0, got $rc"
expect "flat dashboard: runs its start.sh with the arguments" "$out" "ran $PROJECTS_ROOT/dashboard/start.sh --stop"

fake_start "$PROJECTS_ROOT/dashboard/dashboard"
out=$(bash "$start" --stop 2>&1); rc=$?
[ $rc -eq 0 ] && pass "nested dashboard: exit 0" || fail "nested dashboard: exit 0, got $rc"
expect "nested dashboard: wins over the flat one" "$out" "ran $PROJECTS_ROOT/dashboard/dashboard/start.sh --stop"
done_testing
