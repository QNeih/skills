#!/usr/bin/env bash
# Removes the project's finished worktrees and their local branches; lists every other one.
# Run from inside the project (main checkout, a worktree or a subfolder).
#   prune-worktrees.sh [--dry-run]    --dry-run fetches and prints the same lines, and removes nothing
# Which worktree is a **finished worktree** is defined in the skills repo's GLOSSARY.md; `verdict`
# below applies that rule. Criteria (b) and (c) cost a lookup: gh for the merged PR, and
# tickets.sh, next to this script, for the ticket of a ticket branch (hotfix|bugfix|feature/<id>).
# Always kept: the main checkout (never listed), the worktree this script runs in, a locked
# worktree, and the worktree of a session (`claude agents --json --all`, a session's cwd in it).
# One line per linked worktree:
#   removed: <path>
#   kept: <path> — <reason>
#   claude rm <id> — <path>      finished, but session <id> works in it: that command removes both
# When `claude agents` can't be read, finished worktrees are kept, since any could hold a session.
# A lookup that fails is the keep reason: `fetch failed: <msg>` (only where the worktree would be
# finished by its commits on origin alone), `PR lookup failed: <msg>`, `ticket lookup failed: <msg>`.
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

# Fresh origin refs, so "on origin" reads what origin holds now. Without an origin nothing is on it.
fetch_err=
err=$(git -C "$dir" fetch -q --prune origin 2>&1) || fetch_err=$(head -1 <<<"${err:-no message}")
errf=$(mktemp); trap 'rm -f "$errf"' EXIT

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

# verdict <path> <branch or empty>: sets `why` to the reason the worktree is not finished,
# empty when it is finished
verdict() {
  local path=$1 branch=$2 tip prs id ticket pushed=0
  tip=$(git -C "$path" rev-parse -q --verify HEAD 2>/dev/null) || { why="not finished"; return; }
  [ -n "$(git -C "$path" rev-list -1 HEAD --not --remotes=origin 2>/dev/null)" ] || pushed=1
  why=
  # (a) every commit on an origin ref, read from refs the fetch just refreshed
  [ "$pushed" -eq 0 ] || [ -n "$fetch_err" ] || return 0
  if [ -n "$branch" ]; then
    # (b) the branch tip is the head commit of a merged PR
    if prs=$(cd "$dir" && gh pr list --head "$branch" --state merged --json headRefOid 2>"$errf") &&
       jq -e 'type == "array"' <<<"$prs" >/dev/null 2>&1; then
      [ "$(jq --arg tip "$tip" 'any(.[]; .headRefOid == $tip)' <<<"$prs")" != true ] || return 0
      [ "$(jq 'length' <<<"$prs")" -eq 0 ] || why="commits after the merged PR"
    else
      why="PR lookup failed: $(head -1 "$errf" | grep . || echo "unreadable answer")"
    fi
  fi
  [ -z "$fetch_err" ] || [ "$pushed" -eq 0 ] || why="fetch failed: $fetch_err"
  [ -z "$why" ] || return 0
  # (c) the ticket is closed and every commit is on an origin ref; here some commit is not
  why="not finished"
  [ -n "$branch" ] && [ "$board" = github ] || return 0
  id=$(ticket_of "$branch"); [ -n "$id" ] || return 0
  if ticket=$(cd "$dir" && bash "$here/tickets.sh" show "$id" 2>"$errf"); then
    [ "$(jq -r '.state' <<<"$ticket" 2>/dev/null)" != CLOSED ] || why="unpushed commits"
  else
    why="ticket lookup failed: $(head -1 "$errf" | grep . || echo "no message")"
  fi
}

rc=0
# judge <path> <branch or empty> <locked 0|1>: prints the worktree's line, removes it when due
judge() {
  local path=$1 branch=$2 locked=$3 ids id err why
  [ "$path" != "$dir" ] || return 0
  [ "$locked" -eq 0 ] || { echo "kept: $path — locked"; return 0; }
  [ "$path" != "$current" ] || { echo "kept: $path — current worktree"; return 0; }
  [ -d "$path" ] || { echo "kept: $path — folder missing"; return 0; }
  [ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ] || { echo "kept: $path — uncommitted changes"; return 0; }
  verdict "$path" "$branch"
  [ -z "$why" ] || { echo "kept: $path — $why"; return 0; }
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
