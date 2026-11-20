#!/usr/bin/env bash
# Commit and push a brain. Usage: brain-sync.sh <brain path>
# Stages everything not ignored except project wiki folders (left out by
# pathspec, whatever the ignore list says), commits with the date as message
# when something changed, and pushes when the branch has no upstream or is
# ahead of it. Nothing to commit and nothing to push never touches the network.
set -euo pipefail

brain=${1:?usage: brain-sync.sh <brain path>}
[ -d "$brain/.git" ] || { echo "brain-sync: $brain is not a git repo" >&2; exit 1; }

git -C "$brain" add -A -- . ':(exclude,glob)wiki/projects/*/**'
if ! git -C "$brain" diff --cached --quiet; then
  git -C "$brain" commit -q -m "$(date +%F)"
fi

# An earlier failed push leaves a commit ahead of upstream; it goes out now.
if ! git -C "$brain" rev-parse -q --verify '@{u}' >/dev/null 2>&1 \
  || [ "$(git -C "$brain" rev-list --count '@{u}..HEAD')" -gt 0 ]; then
  git -C "$brain" push -q -u origin HEAD
fi
