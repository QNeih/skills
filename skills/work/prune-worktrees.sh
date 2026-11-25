#!/usr/bin/env bash
# Removes the project's finished worktrees and their local branches; lists every other one.
# Run from inside the project (main checkout, a worktree or a subfolder).
#   prune-worktrees.sh [--dry-run]    --dry-run only prints: no fetch, nothing removed
# A linked worktree is finished when it has no modified tracked file and no untracked file
# (ignored files such as .scratch/ and .handoffs/ don't count and go with it), and one of:
#   a) every commit of its HEAD is on an origin ref
#   b) its branch has a merged PR (gh pr list --head <branch> --state merged); squash merges
#      leave the branch's own commits off origin
#   c) its branch is a ticket branch (hotfix|bugfix|feature/<id>) of a GitHub board and
#      tickets.sh, next to this script, shows the ticket as closed
# A detached worktree is judged by (a) only.
# Always kept: the main checkout (never listed), the worktree this script runs in, a locked
# worktree, and the worktree of a session (`claude agents --json --all`, a session's cwd in it).
# One line per linked worktree:
#   removed: <path>
#   kept: <path> — <reason>
#   claude rm <id> — <path>      finished, but session <id> works in it: that command removes both
# When `claude agents` can't be read, finished worktrees are kept, since any could hold a session.
# Exit: 0; 1 when the folder is no git checkout or a removal failed.
set -u
here=$(cd "$(dirname "$0")" && pwd)

dry=0
case ${1:-} in
  '') ;;
  --dry-run) dry=1 ;;
  *) echo "usage: prune-worktrees.sh [--dry-run]" >&2; exit 1 ;;
esac

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  { echo "prune-worktrees.sh: $PWD is not in a git checkout" >&2; exit 1; }
dir=$(cd "$(dirname "$common")" && pwd -P)
current=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)

# Fresh origin refs, so (a) reads what origin holds now; without an origin (a) is never true
[ "$dry" -eq 1 ] || git -C "$dir" fetch -q --prune origin 2>/dev/null

# Sessions as `<id> TAB <cwd>` lines; sessions_ok=0 when they can't be read
claude=$(command -v claude || echo "$HOME/.local/bin/claude")
sessions_ok=0; sessions=
if raw=$(cd "$dir" && "$claude" agents --json --all --cwd "$dir" 2>/dev/null) &&
   jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1; then
  sessions_ok=1; sessions=$(jq -r '.[] | "\(.id)\t\(.cwd)"' <<<"$raw")
fi

lookup=$(cd "$dir" && bash "$here/project.sh")
board=$(sed -n 's/^board: //p' <<<"$lookup"); key=$(sed -n 's/^key: //p' <<<"$lookup")

# session_ids <path>: ids of the sessions whose cwd is the worktree or a folder in it
session_ids() {
  [ -n "$sessions" ] || return 0
  awk -F'\t' -v p="$1" '$2 == p || index($2, p "/") == 1 { print $1 }' <<<"$sessions"
}

# ticket_of <branch>: the ticket id of a ticket branch of this board, else nothing
ticket_of() {
  local id
  case $1 in hotfix/*|bugfix/*|feature/*) id=${1#*/} ;; *) return 0 ;; esac
  if [ -n "$key" ]; then
    [ "${id%-*}" = "$key" ] || return 0
    case ${id##*-} in ''|*[!0-9]*) return 0 ;; esac
  else
    case $id in ''|*[!0-9]*) return 0 ;; esac
  fi
  echo "$id"
}

# finished <path> <branch or empty>: true by (a), (b) or (c)
finished() {
  local path=$1 branch=$2 id
  [ -z "$(git -C "$path" rev-list -1 HEAD --not --remotes=origin 2>/dev/null)" ] &&
    git -C "$path" rev-parse -q --verify HEAD >/dev/null 2>&1 && return 0
  [ -n "$branch" ] || return 1
  [ "$( (cd "$dir" && gh pr list --head "$branch" --state merged --json number 2>/dev/null) | jq 'length' 2>/dev/null)" -gt 0 ] 2>/dev/null && return 0
  [ "$board" = github ] || return 1
  id=$(ticket_of "$branch"); [ -n "$id" ] || return 1
  [ "$( (cd "$dir" && bash "$here/tickets.sh" show "$id" 2>/dev/null) | jq -r '.state' 2>/dev/null)" = CLOSED ]
}

rc=0
# judge <path> <branch or empty> <locked 0|1>: prints the worktree's line, removes it when due
judge() {
  local path=$1 branch=$2 locked=$3 ids id err
  [ "$path" != "$dir" ] || return 0
  [ "$locked" -eq 0 ] || { echo "kept: $path — locked"; return 0; }
  [ "$path" != "$current" ] || { echo "kept: $path — current worktree"; return 0; }
  [ -d "$path" ] || { echo "kept: $path — folder missing"; return 0; }
  [ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ] || { echo "kept: $path — uncommitted changes"; return 0; }
  finished "$path" "$branch" || { echo "kept: $path — not finished"; return 0; }
  [ "$sessions_ok" -eq 1 ] || { echo "kept: $path — sessions unknown"; return 0; }
  ids=$(session_ids "$path")
  if [ -n "$ids" ]; then
    for id in $ids; do echo "claude rm $id — $path"; done
    return 0
  fi
  if [ "$dry" -eq 0 ]; then
    err=$(git -C "$dir" worktree remove "$path" 2>&1) ||
      { echo "kept: $path — could not remove: $(head -1 <<<"$err")"; rc=1; return 0; }
    [ -z "$branch" ] || git -C "$dir" branch -q -D "$branch" 2>/dev/null ||
      { echo "removed: $path"; echo "prune-worktrees.sh: could not delete branch $branch" >&2; rc=1; return 0; }
  fi
  echo "removed: $path"
}

path=; branch=; locked=0
while IFS= read -r line; do
  case $line in
    'worktree '*) path=${line#worktree } ;;
    'branch refs/heads/'*) branch=${line#branch refs/heads/} ;;
    locked*) locked=1 ;;
    '') [ -z "$path" ] || judge "$path" "$branch" "$locked"; path=; branch=; locked=0 ;;
  esac
done < <(git -C "$dir" worktree list --porcelain; echo)
exit $rc
