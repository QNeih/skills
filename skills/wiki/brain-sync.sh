#!/usr/bin/env bash
# Commit and push a brain. Usage: brain-sync.sh <brain path>
# Stages everything not ignored, commits with the date as message when something
# changed, pushes. Project wiki folders are never part of the commit.
set -euo pipefail

brain=${1:?usage: brain-sync.sh <brain path>}
[ -d "$brain/.git" ] || { echo "brain-sync: $brain is not a git repo" >&2; exit 1; }

wiki_line='Projects/*/wiki/'
touch "$brain/.gitignore"
grep -qxF -- "$wiki_line" "$brain/.gitignore" || printf '%s\n' "$wiki_line" >> "$brain/.gitignore"

git -C "$brain" add -A
if ! git -C "$brain" diff --cached --quiet; then
  git -C "$brain" commit -q -m "$(date +%F)"
fi

# Push even without a new commit, so an earlier failed push is retried.
git -C "$brain" push -q origin HEAD
