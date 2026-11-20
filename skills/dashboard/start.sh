#!/usr/bin/env bash
# Runs the dashboard's own start script; the dashboard lives in its own repo under the projects root.
# Arguments are passed on (e.g. --stop).
set -eu
# Nested layout (dashboard/dashboard) first, then flat (dashboard)
root="${PROJECTS_ROOT:-$HOME/Projects}"
script="$root/dashboard/dashboard/start.sh"
[ -x "$script" ] || script="$root/dashboard/start.sh"
[ -x "$script" ] || { echo "error: dashboard repo not found: no start.sh in $root/dashboard/dashboard or $root/dashboard" >&2; exit 1; }
exec "$script" "$@"
