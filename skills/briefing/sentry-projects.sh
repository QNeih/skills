#!/usr/bin/env bash
# Sentry projects of a repo. Prints `sentry: <org>/<project>` lines, or `sentry: none` and
# `reason:`; always exits 0 so callers read the reason.
#   sentry-projects.sh <repo dir> [project note]
# The note's `sentry` property (one or more `org/project`, comma-separated) wins. Otherwise every
# DSN in the repo's tracked files (`*.ingest*.sentry.io/<id>`) maps to its project via `sentry api`.
set -u
dir=${1:-} note=${2:-}
none() { echo "sentry: none"; echo "reason: $1"; exit 0; }

if [ -n "$note" ] && [ -f "$note" ]; then
  override=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, "sentry:") == 1 { v = substr($0, 8); gsub(/["\x27]/, "", v); print v; exit }' "$note")
  if [ -n "$override" ]; then
    tr ', ' '\n\n' <<<"$override" | grep . | sed 's/^/sentry: /'
    exit 0
  fi
fi

git -C "$dir" rev-parse 2>/dev/null || none "$dir is not a git repo"
ids=$(git -C "$dir" grep -hIoE '[A-Za-z0-9.-]*\.ingest[A-Za-z0-9.-]*\.sentry\.io/[0-9]+' 2>/dev/null |
  sed 's|.*/||' | sort -u)
[ -n "$ids" ] || none "no Sentry DSN committed in $dir; set sentry: <org>/<project> in the project note"

# ponytail: one page of projects/ (100); paginate if an account ever sees more
projects=$(sentry api projects/ 2>&1) || none "sentry api projects/ failed: $(head -1 <<<"$projects")"
found= missing=
for id in $ids; do
  p=$(jq -r --arg id "$id" '.[] | select(.id == $id) | "\(.organization.slug)/\(.slug)"' <<<"$projects")
  if [ -n "$p" ]; then found+="sentry: $p"$'\n'
  else missing+="Sentry project id $id (from a DSN) not found by sentry api projects/"$'\n'; fi
done
[ -n "$found" ] || none "$(head -1 <<<"$missing")"
printf '%s' "$found"
[ -z "$missing" ] || printf '%s' "$missing" | sed 's/^/skipped: /'
