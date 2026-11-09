#!/usr/bin/env bash
# Runs the script tests; with --live also the `claude -p` tests (live-*.sh, cost tokens).
cd "$(dirname "$0")" || exit 1
rc=0
tests=(shared-copies.sh test-*.sh)
[ "${1:-}" = --live ] && tests+=(live-*.sh)
for t in "${tests[@]}"; do
  [ -f "$t" ] || continue
  echo "== $t"
  bash "$t" || rc=1
done
[ $rc -eq 0 ] && echo "PASS" || echo "FAILED"
exit $rc
