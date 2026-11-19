#!/usr/bin/env bash
# File parts of the board step (BOARD.md): the GitHub board of a project in the folder layout
# <projects root>/<name>/{<name>,wiki}.
#   board.sh create PROJECT_DIR [--owner OWNER]
#       make what is missing: private repo <name>-wiki, the Project <name>, labels urgent, bug,
#       hotfix, the link Project -> wiki repo, the wiki clone at <name>/wiki, wiki/project.md.
#       OWNER defaults to the owner of PROJECT_DIR's origin. Safe to rerun: what exists is kept.
#       Prints `wiki:`, `repo:`, `number:` and `owner:` lines.
#   board.sh set WIKI_DIR KEY VALUE
#       set one line of WIKI_DIR/project.md (replaced, or added at the end of the front matter)
set -eu

# owner/name of the origin of git folder $1 (https, ssh and scp-like URLs), else nothing
origin_repo() {
  local u; u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  u=${u%/}; u=${u%.git}
  awk -F'[/:]' 'NF >= 2 { print $(NF-1) "/" $NF }' <<<"$u"
}

# set_line FILE KEY VALUE: one front matter line; creates the front matter when the file has none
set_line() {
  local file=$1 key=$2 value=$3
  if [ "$(head -1 "$file" 2>/dev/null)" != --- ]; then
    { printf -- '---\n---\n'; cat "$file" 2>/dev/null || true; } > "$file.tmp" && mv "$file.tmp" "$file"
  fi
  awk -v key="$key" -v line="$key: $value" '
    NR > 1 && !end && index($0, key ":") == 1 { print line; set = 1; next }
    NR > 1 && !end && $0 == "---" { if (!set) print line; end = 1 }
    { print }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

cmd=${1:-}
case $cmd in
create)
  dir=${2:?usage: board.sh create PROJECT_DIR [--owner OWNER]}
  owner=
  if [ "${3:-}" = --owner ]; then owner=${4:?--owner needs a value}; fi
  dir=$(cd "$dir" && pwd -P)
  root=$(dirname "$dir"); name=$(basename "$root"); wiki="$root/wiki"
  if [ -z "$owner" ]; then
    pr=$(origin_repo "$dir"); owner=${pr%%/*}
  fi
  [ -n "$owner" ] || { echo "board.sh: $dir has no origin; pass --owner OWNER" >&2; exit 1; }
  repo="$owner/$name-wiki"

  # Wiki repo: private, same owner as the project repo
  if [ -z "$(gh repo view "$repo" --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)" ]; then
    gh repo create "$repo" --private
  fi

  # Wiki clone at <name>/wiki
  [ -d "$wiki/.git" ] || gh repo clone "$repo" "$wiki"

  # Project: the one project.md names, else the one titled <name>, else a new one
  number=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } /^project:/ { sub(/^project:[ \t]*/, ""); print; exit }' "$wiki/project.md" 2>/dev/null || true)
  if [ -z "$number" ]; then
    number=$(gh project list --owner "$owner" --format json --jq ".projects[] | select(.title == \"$name\") | .number" | head -1)
    [ -n "$number" ] || number=$(gh project create --owner "$owner" --title "$name" --format json --jq .number)
    gh project link "$number" --owner "$owner" --repo "$repo"
  fi

  # --force makes an existing label a no-op update
  for l in urgent bug hotfix; do gh label create "$l" --repo "$repo" --force; done

  set_line "$wiki/project.md" board github
  set_line "$wiki/project.md" project "$number"
  echo "wiki: $wiki"; echo "repo: $repo"; echo "number: $number"; echo "owner: $owner"
  ;;
set)
  wiki=${2:?usage: board.sh set WIKI_DIR KEY VALUE}; key=${3:?missing KEY}; value=${4:?missing VALUE}
  set_line "$wiki/project.md" "$key" "$value"
  echo "saved: $key in $wiki/project.md"
  ;;
*) echo "usage: board.sh create PROJECT_DIR [--owner OWNER] | set WIKI_DIR KEY VALUE" >&2; exit 2 ;;
esac
