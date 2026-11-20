#!/usr/bin/env bash
# Project lookup from the folder layout: <projects root>/<name>/{<name>,wiki}. Prints `key: value`
# lines; always exits 0 so callers read the reason.
#   project.sh              project of the current folder (main checkout, worktree or subfolder):
#                           dir, project, wiki, board, repo, number, owner, key
#   project.sh --name NAME  same for the project folder <projects root>/NAME/NAME (--note is an alias)
# Settings come from wiki/project.md (front matter): board, repo, project (the Project's number),
# owner, key. `board` defaults to github; `repo` and `owner` default to the wiki's origin, `owner`
# then to the project repo's origin. A line with no value is not printed.
# A project without a wiki folder keeps the same settings in <main checkout>/.claude/project.md;
# `repo` and `owner` then default to the code repo's origin and no `wiki:` line is printed.
# With neither file the output is `project: none` and a reason naming both places.
# Env: PROJECTS_ROOT (folder holding the projects), needed only for --name.
set -u

# NFC, lowercase, spaces and hyphens removed
norm() { perl -CSA -MUnicode::Normalize -le '$_ = lc NFC shift; s/[ -]//g; print' "$1"; }

# Main checkout of the folder (also from worktrees and subfolders); no git → the folder itself
main_dir() {
  local common
  if common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    (cd "$(dirname "$common")" && pwd -P)
  else
    (cd "$1" && pwd -P)
  fi
}

# Front matter property of a file, quotes stripped
prop() {
  awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t"\x27]+|[ \t"\x27]+$/, "", v); print v; exit }' "$1" 2>/dev/null
}

# owner/name of the origin of git folder $1 (https, ssh and scp-like URLs), else nothing
origin_repo() {
  local u; u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  u=${u%/}; u=${u%.git}
  awk -F'[/:]' 'NF >= 2 { print $(NF-1) "/" $NF }' <<<"$u"
}

none() { echo "project: none"; echo "reason: $1"; exit 0; }

# Print the lookup lines for the main checkout $1
report() {
  local dir=$1 root wiki settings board repo owner number key pr base
  root=$(dirname "$dir"); wiki="$root/wiki"; settings="$wiki/project.md"
  echo "dir: $dir"
  if [ -d "$wiki" ]; then
    base=$wiki
  elif [ -f "$dir/.claude/project.md" ]; then
    base=$dir; settings="$dir/.claude/project.md"
  else
    none "no wiki at $wiki and no settings at $dir/.claude/project.md: run the board step to create the wiki and the board"
  fi
  echo "project: $(basename "$root")"
  [ "$base" != "$wiki" ] || echo "wiki: $wiki"
  board=$(prop "$settings" board)
  echo "board: ${board:-github}"
  repo=$(prop "$settings" repo); [ -n "$repo" ] || repo=$(origin_repo "$base")
  owner=$(prop "$settings" owner)
  [ -n "$owner" ] || owner=${repo%%/*}
  [ -n "$owner" ] || { pr=$(origin_repo "$dir"); owner=${pr%%/*}; }
  number=$(prop "$settings" project); key=$(prop "$settings" key)
  [ -z "$repo" ] || echo "repo: $repo"
  [ -z "$number" ] || echo "number: $number"
  [ -z "$owner" ] || echo "owner: $owner"
  [ -z "$key" ] || echo "key: $key"
  exit 0
}

if [ "${1:-}" = --name ] || [ "${1:-}" = --note ]; then
  [ -n "${PROJECTS_ROOT:-}" ] || none "PROJECTS_ROOT must be set"
  PROJECTS_ROOT=$(cd "$PROJECTS_ROOT" && pwd -P) || none "projects root $PROJECTS_ROOT not found"
  want=$(norm "${2:-}")
  for d in "$PROJECTS_ROOT"/*/; do
    d=${d%/}
    if [ "$(norm "${d##*/}")" = "$want" ] && [ -d "$d/${d##*/}" ]; then report "$d/${d##*/}"; fi
  done
  none "no project folder named ${2:-} under the projects root"
fi

report "$(main_dir "$PWD")"
