#!/usr/bin/env bash
# Sentry projects of a repo. Prints `sentry: <org>/<project>` lines, or `sentry: none` and
# `reason:`; always exits 0 so callers read the reason.
#   sentry-projects.sh <repo dir>
# The `sentry` setting of the settings file (read through settings.sh; one or more `org/project`,
# comma-separated) wins. Otherwise every DSN in the repo's tracked files
# (`*.ingest*.sentry.io/<id>`) maps to its project via `sentry api`.
set -u
dir=${1:-}
none() { echo "sentry: none"; echo "reason: $1"; exit 0; }

[ -d "$dir" ] || none "$dir is not a folder"
# quotes around single items of a list (`"a/b", "c/d"`) are dropped too; `get` strips only the ends
override=$(bash "$(dirname "${BASH_SOURCE[0]}")/settings.sh" get "$dir" sentry | tr -d "\"'")
if [ -n "$override" ]; then
  tr ', ' '\n\n' <<<"$override" | grep . | sed 's/^/sentry: /'
  exit 0
fi

git -C "$dir" rev-parse 2>/dev/null || none "$dir is not a git repo"
ids=$(git -C "$dir" grep -hIoE '[A-Za-z0-9.-]*\.ingest[A-Za-z0-9.-]*\.sentry\.io/[0-9]+' 2>/dev/null |
  sed 's|.*/||' | sort -u)
[ -n "$ids" ] || none "no Sentry DSN committed in $dir; set sentry: <org>/<project> in $dir/.claude/project.md"

# Projects of every organization the account sees (the user-level projects/ endpoint can be empty for org tokens).
# ponytail: one page per organization (100 projects); paginate if an organization ever has more
orgs=$(sentry api organizations/ 2>&1) || none "sentry api organizations/ failed: $(head -1 <<<"$orgs")"
projects=
for org in $(jq -r '.[].slug' <<<"$orgs" 2>/dev/null); do
  list=$(sentry api "organizations/$org/projects/" 2>&1) ||
    none "sentry api organizations/$org/projects/ failed: $(head -1 <<<"$list")"
  projects+=$(jq -r --arg o "$org" '.[] | "\(.id) \($o)/\(.slug)"' <<<"$list")$'\n'
done
found= missing=
for id in $ids; do
  p=$(awk -v id="$id" '$1 == id { print $2; exit }' <<<"$projects")
  if [ -n "$p" ]; then found+="sentry: $p"$'\n'; else missing+="$id "; fi
done
# DSNs outside the account's organizations (test fixtures, vendors' DSNs) aren't this project's Sentry
[ -n "$found" ] || none "no committed DSN belongs to a Sentry organization you can see (project ids: ${missing% })"
printf '%s' "$found"
for id in $missing; do echo "skipped: Sentry project id $id (from a DSN) is not in your Sentry organizations"; done
