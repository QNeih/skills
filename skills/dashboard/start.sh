#!/usr/bin/env bash
# Starts the dashboard server if it isn't running, then opens it full screen.
#   start.sh          start (if needed) and open
#   start.sh --stop   stop the server
# Env: VAULT, PROJECTS_ROOT (passed on to the server); DASHBOARD_PORT (default 4777).
set -eu
export VAULT=${VAULT:-"$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/lise"}
export PROJECTS_ROOT=${PROJECTS_ROOT:-"$HOME/Projects"}
here=$(cd "$(dirname "$0")" && pwd)
port=${DASHBOARD_PORT:-4777}
url="http://127.0.0.1:$port/"
state=$HOME/.claude/dashboard
pidfile=$state/server.pid
mkdir -p "$state"

running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

if [ "${1:-}" = --stop ]; then
  running && kill "$(cat "$pidfile")" && echo "stopped" || echo "not running"
  rm -f "$pidfile"; exit 0
fi

# A server started before server.py changed serves old code: restart it.
if running && [ "$here/server.py" -nt "$pidfile" ]; then kill "$(cat "$pidfile")"; rm -f "$pidfile"; fi

if ! running; then
  nohup python3 "$here/server.py" --port "$port" >> "$state/server.log" 2>&1 &
  echo $! > "$pidfile"
  for _ in $(seq 50); do curl -fs -o /dev/null "$url" && break; sleep 0.1; done
  curl -fs -o /dev/null "$url" || { echo "error: server did not start — see $state/server.log"; tail -5 "$state/server.log"; exit 1; }
fi

# The dashboard's own Chrome (its own profile) already runs → bring it to the front, no second window.
chrome=$(pgrep -f -- "--user-data-dir=$state/chrome" | while read -r p; do
  ps -o command= -p "$p" | grep -q -- '--type=' || echo "$p"; done | head -1)
if [ -n "$chrome" ]; then
  osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($chrome).activateWithOptions(\$.NSApplicationActivateAllWindows)" >/dev/null
# Chrome app mode: a window without tabs or address bar, full screen. No Chrome → default browser.
elif [ -d "/Applications/Google Chrome.app" ]; then
  open -na "Google Chrome" --args --app="$url" --start-fullscreen --user-data-dir="$state/chrome"
else
  open "$url"
fi
echo "dashboard: $url (pid $(cat "$pidfile"))"
