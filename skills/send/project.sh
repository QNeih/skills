#!/usr/bin/env bash
# Project lookup from the folder layout. Prints `key: value` lines; always exits 0 so callers read
# the reason. A line with no value is not printed.
#   project.sh              project of the current folder (main checkout, worktree or subfolder)
#   project.sh --name NAME  project folder NAME under the projects root, ignoring case, spaces and
#                           hyphens (--note is an alias)
# Layouts:
#   nested  <projects root>/<name>/<name>  the checkout sits in a project folder of its own name;
#                                          a sibling `wiki` folder is optional and holds pages only
#   flat    <projects root>/<name>         the folder is the checkout
# From a folder: nested when the main checkout's parent folder has the checkout's name, else flat.
# With --name: a folder that is no git checkout itself and holds a folder of its own name is
# nested (that inner folder is the checkout); any other folder is flat.
# Settings: the front matter of <main checkout>/.claude/project.md, the only settings file:
# board, project (the GitHub Project's number), owner (the Project's owner), key, repo.
# Lines, in this order:
#   dir:      the main checkout (without git: the folder itself)
#   project:  the checkout folder's name. `none` plus `reason:` when the folder is neither a git
#             checkout nor holds a settings file, or when no folder matches NAME; the lookup
#             ends there
#   wiki:     the sibling wiki folder; only in the nested layout, only when it exists
#   board:    the `board` setting, `github` when the settings file has none. Without a settings
#             file: `none` plus a `reason:` saying the board step has not run, and no line below
#   repo:     owner/name of the code repo: the `repo` setting, else the checkout's origin
#   number:   the `project` setting
#   owner:    the `owner` setting, else the repo's owner
#   key:      the `key` setting; with one, a ticket's id is <key>-<issue number>
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
  local dir=$1 name parent settings board repo owner number key
  name=$(basename "$dir"); parent=$(dirname "$dir"); settings="$dir/.claude/project.md"
  echo "dir: $dir"
  [ -f "$settings" ] || [ -e "$dir/.git" ] ||
    none "$dir is no git checkout and has no settings file .claude/project.md"
  echo "project: $name"
  if [ "$(basename "$parent")" = "$name" ] && [ -d "$parent/wiki" ]; then echo "wiki: $parent/wiki"; fi
  if [ ! -f "$settings" ]; then
    echo "board: none"
    echo "reason: no settings file $settings: the board step has not run"
    exit 0
  fi
  board=$(prop "$settings" board)
  echo "board: ${board:-github}"
  repo=$(prop "$settings" repo); [ -n "$repo" ] || repo=$(origin_repo "$dir")
  owner=$(prop "$settings" owner); [ -n "$owner" ] || owner=${repo%%/*}
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
    [ "$(norm "${d##*/}")" = "$want" ] || continue
    if [ ! -e "$d/.git" ] && [ -d "$d/${d##*/}" ]; then report "$d/${d##*/}"; else report "$d"; fi
  done
  none "no project folder named ${2:-} under the projects root"
fi

report "$(main_dir "$PWD")"
