#!/usr/bin/env bash
# Runs the dashboard's own start script; the dashboard lives in its own repo under the projects root.
# Arguments are passed on (e.g. --stop).
set -eu
script="${PROJECTS_ROOT:-$HOME/Projects}/dashboard/start.sh"
[ -x "$script" ] || { echo "error: dashboard repo not found: $script is missing" >&2; exit 1; }
exec "$script" "$@"
