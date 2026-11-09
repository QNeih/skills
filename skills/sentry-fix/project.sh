#!/usr/bin/env bash
# Project lookup. Prints `key: value` lines; always exits 0 so callers read the reason.
#   project.sh             project of the current folder: project, note, dir, board, key
#   project.sh --note NAME folder of a project note: project, note, dir, board, key
# Env: VAULT (Obsidian vault), PROJECTS_ROOT (folder holding the project checkouts).
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

# Note paths, one per line
notes() {
  local d
  for d in "$VAULT"/Projects/*/; do
    d=${d%/}
    [ -f "$d/${d##*/}.md" ] && echo "$d/${d##*/}.md"
  done
}
note_name() { basename "$1" .md; }

# Frontmatter property of a note, quotes stripped
prop() {
  awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t"\x27]+|[ \t"\x27]+$/, "", v); print v; exit }' "$1"
}

# Repo URL compared ignoring a trailing .git and case
repo_key() { local r; r=$(tr '[:upper:]' '[:lower:]' <<<"$1"); r=${r%/}; echo "${r%.git}"; }

# Notes whose repo equals the origin of git folder $1
by_repo() {
  local n r origin
  origin=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  origin=$(repo_key "$origin")
  while IFS= read -r n; do
    r=$(prop "$n" repo)
    [ -n "$r" ] && [ "$(repo_key "$r")" = "$origin" ] && echo "$n"
  done < <(notes)
}

# Note whose name matches the folder name of $1
by_name() {
  local n want; want=$(norm "$(basename "$1")")
  while IFS= read -r n; do
    [ "$(norm "$(note_name "$n")")" = "$want" ] && echo "$n"
  done < <(notes)
}

# Note whose local equals folder $1 or is a parent of it; prints "<note>\t<local>"
by_local() {
  local n l
  while IFS= read -r n; do
    l=$(prop "$n" local)
    [ -n "$l" ] || continue
    l=${l/#\~/$HOME}; l=${l%/}; [ -d "$l" ] && l=$(cd "$l" && pwd -P)
    case "$1/" in "$l"/*) printf '%s\t%s\n' "$n" "$l" ;; esac
  done < <(notes)
}

# Folders one level under the projects root whose origin equals repo $1
clones() {
  local d o want; want=$(repo_key "$1")
  for d in "$PROJECTS_ROOT"/*/; do
    o=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
    [ "$(repo_key "$o")" = "$want" ] && (cd "$d" && pwd -P)
  done
}

# Most frequent KEY among KEY-123 ids on stdin, counting each id once
# (so UTF-8 or SHA-256 repeated in many commits loses to a real key with several tickets)
top_key() { grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | sort -u | sed 's/-[0-9]*$//' | sort | uniq -c | sort -rn | awk 'NR == 1 { print $2 }'; }

# board and key lines for note $1, checkout $2
board() {
  local name file override key=
  name=$(note_name "$1"); file="$(dirname "$1")/$name Board.md"
  override=$(prop "$1" board)
  if [ -f "$file" ]; then
    echo "board: vault"; echo "board-file: $file"
    key=$(grep -oE '\*\*[A-Z][A-Z0-9]*-[0-9]+ ·' "$file" | top_key)
  elif [ -n "$override" ]; then
    echo "board: $override"
  elif [ -d "$2" ] && git -C "$2" rev-parse 2>/dev/null; then
    key=$({ git -C "$2" for-each-ref --format='%(refname:short)' refs/heads refs/remotes
            git -C "$2" log -300 --format=%s; } | top_key)
    [ -n "$key" ] && echo "board: jira-candidate" || echo "board: none"
  else
    echo "board: none"
  fi
  [ -z "$key" ] || echo "key: $key"
}

none() { echo "project: none"; echo "reason: $1"; exit 0; }
found() { echo "project: $(note_name "$1")"; echo "note: $1"; }

if [ -z "${VAULT:-}" ] || [ -z "${PROJECTS_ROOT:-}" ]; then none "VAULT and PROJECTS_ROOT must be set"; fi
VAULT=$(cd "$VAULT" && pwd -P) || none "vault $VAULT not found"
PROJECTS_ROOT=$(cd "$PROJECTS_ROOT" && pwd -P) || none "projects root $PROJECTS_ROOT not found"

# Reverse lookup: folder of note named $1
if [ "${1:-}" = --note ]; then
  note=$(by_name "${2:-}" | head -1)
  [ -n "$note" ] || none "no project note named ${2:-}"
  found "$note"
  hasdir() { echo "dir: $1"; board "$note" "$1"; exit 0; }
  nodir() { echo "dir: none"; echo "reason: $1"; board "$note" ""; exit 0; }
  loc=$(prop "$note" local)
  if [ -n "$loc" ]; then loc=${loc/#\~/$HOME}; hasdir "${loc%/}"; fi
  repo=$(prop "$note" repo) name=$(note_name "$note")
  if [ -n "$repo" ]; then
    c=$(clones "$repo")
    [ "$(wc -l <<<"$c")" -gt 1 ] && nodir "two clones of $repo under the projects root: $(echo $c)"
    [ -n "$c" ] && hasdir "$c"
  fi
  for d in "$PROJECTS_ROOT"/*/; do
    d=${d%/}
    [ "$(norm "${d##*/}")" = "$(norm "$name")" ] && hasdir "$d"
  done
  [ -n "$repo" ] && nodir "no folder under the projects root with origin $repo or named like $name"
  nodir "no folder under the projects root named like $name"
fi

dir=$(main_dir "$PWD")
IFS=$'\t' read -r note loc < <(by_local "$dir" | head -1)
if [ -n "$note" ] && ! git -C "$dir" rev-parse 2>/dev/null; then dir=$loc; fi
echo "dir: $dir"
if [ -z "$note" ]; then
  case "$dir/" in "$PROJECTS_ROOT"/*) ;; *) none "$dir is outside the projects root $PROJECTS_ROOT" ;; esac
  note=$(by_repo "$dir" | head -1)
  if [ -n "$note" ]; then
    repo=$(prop "$note" repo)
    c=$(clones "$repo")
    [ "$(wc -l <<<"$c")" -gt 1 ] && none "two clones of $repo under the projects root: $(echo $c)"
  else
    note=$(by_name "$dir" | head -1)
  fi
fi
if [ -z "$note" ]; then
  origin=$(git -C "$dir" remote get-url origin 2>/dev/null)
  if [ -n "$origin" ]; then none "no project note with repo $origin or named like ${dir##*/}"; fi
  none "no project note named like ${dir##*/}"
fi
found "$note"
board "$note" "$dir"
