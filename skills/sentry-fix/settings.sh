#!/usr/bin/env bash
# The settings file of a project, <main checkout>/.claude/project.md: the one script that reads
# and writes its front matter. DIR is the checkout, or any folder inside it (a worktree included).
#   settings.sh get DIR KEY
#       prints the value of KEY, quotes at its ends stripped; prints nothing when the file or the
#       line is missing. Exits 0.
#   settings.sh set DIR KEY VALUE
#       sets one line of the front matter (replaced, or added at its end); creates the file and
#       its front matter when missing. Commits nothing. Prints `saved: KEY in FILE`.
#   settings.sh publish DIR [KEY VALUE]
#       with KEY VALUE, sets the line first; then commits the settings file alone and pushes it,
#       so every worktree and colleague reads the same settings. Prints one line and exits 0 on:
#         published: FILE                           committed and pushed
#         nothing to publish: FILE                  the file has no uncommitted change
#         not published: DIR is no git repository   the file is saved, nothing to commit to
#       Prints `could not fix: CAUSE` and exits 1, leaving the file saved and uncommitted, when
#       the checkout is on a branch other than the default branch, or the push fails.
set -eu

# Main checkout of the folder (also from worktrees and subfolders); no git → the folder itself
main_dir() {
  local common
  if common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    (cd "$(dirname "$common")" && pwd -P)
  else
    (cd "$1" && pwd -P)
  fi
}

# get_line KEY: front matter property of the settings file, quotes at its ends stripped
get_line() {
  awk -v k="$1" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t"\x27]+|[ \t"\x27]+$/, "", v); print v; exit }' "$settings" 2>/dev/null || true
}

# set_line KEY VALUE: one front matter line of the settings file; creates file and front matter when missing
set_line() {
  mkdir -p "$(dirname "$settings")"
  if [ "$(head -1 "$settings" 2>/dev/null)" != --- ]; then
    { printf -- '---\n---\n'; cat "$settings" 2>/dev/null || true; } > "$settings.tmp" && mv "$settings.tmp" "$settings"
  fi
  KEY=$1 LINE="$1: $2" awk '
    NR > 1 && !end && index($0, ENVIRON["KEY"] ":") == 1 { print ENVIRON["LINE"]; set = 1; next }
    NR > 1 && !end && $0 == "---" { if (!set) print ENVIRON["LINE"]; end = 1 }
    { print }' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
}

# default_branch: the branch origin's HEAD names, else main or master, whichever exists
default_branch() {
  local b
  if b=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); then echo "${b#origin/}"; return; fi
  for b in main master; do
    ! git -C "$dir" show-ref --verify --quiet "refs/heads/$b" || { echo "$b"; return; }
  done
}

# publish: commit the settings file alone on the default branch and push it
publish() {
  local branch default err
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "not published: $dir is no git repository"; return 0; }
  [ -n "$(git -C "$dir" status --porcelain -- .claude/project.md)" ] || { echo "nothing to publish: $settings"; return 0; }
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || true)
  default=$(default_branch)
  if [ -z "$branch" ] || [ "$branch" != "$default" ]; then
    echo "could not fix: $dir is on ${branch:-a detached HEAD}, not the default branch ${default:-(none found)}; $settings stays uncommitted"
    return 1
  fi
  git -C "$dir" add .claude/project.md
  git -C "$dir" commit -q -m "Update project settings" -- .claude/project.md
  if ! err=$(git -C "$dir" push -q -u origin HEAD 2>&1); then
    git -C "$dir" reset -q --soft HEAD~1
    git -C "$dir" reset -q -- .claude/project.md
    echo "could not fix: push of $branch failed: $(head -1 <<<"$err"); $settings stays uncommitted"
    return 1
  fi
  echo "published: $settings"
}

usage="usage: settings.sh get DIR KEY | set DIR KEY VALUE | publish DIR [KEY VALUE]"
cmd=${1:-}; dir=${2:?$usage}
case $cmd in
get|set|publish) ;;
*) echo "$usage" >&2; exit 2 ;;
esac
dir=$(main_dir "$dir"); settings="$dir/.claude/project.md"
case $cmd in
get)
  get_line "${3:?missing KEY}"
  ;;
set)
  set_line "${3:?missing KEY}" "${4:?missing VALUE}"
  echo "saved: $3 in $settings"
  ;;
publish)
  [ $# -eq 2 ] || set_line "${3:?missing KEY}" "${4:?missing VALUE}"
  publish
  ;;
esac
