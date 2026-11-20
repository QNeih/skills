#!/usr/bin/env bash
# File parts of the board step (BOARD.md): a project's GitHub board and its settings file,
# <main checkout>/.claude/project.md. PROJECT_DIR is the checkout, or any folder inside it.
#   board.sh create PROJECT_DIR [--owner OWNER] [--key KEY]
#       make what is missing: the Project titled `<name> (<KEY>)` (`<name>` without a key), its
#       link to the code repo, the labels urgent, bug and hotfix in the code repo, and the settings
#       file with board, project, key, and owner when it is not the repo's owner.
#       <name> is the checkout folder's name. The code repo is the `repo` setting, else the
#       checkout's origin; it has to exist on GitHub. OWNER, the Project's owner, defaults to the
#       `owner` setting, else the repo's owner; KEY defaults to the `key` setting.
#       The Project is found again by the `project` setting, else by its title, with or without
#       the ` (<KEY>)` part: a title's key is taken over when no key is known, and a title
#       without the key gets it added. A KEY given later, for a board that has none, is added to
#       the title and the settings too.
#       Safe to rerun: what exists is kept. Commits nothing.
#       Prints `settings:`, `repo:`, `number:`, `owner:` and `key:` lines.
#   board.sh set PROJECT_DIR KEY VALUE
#       set one line of the settings file (replaced, or added at the end of the front matter);
#       creates the file when it is missing
set -eu
die() { echo "board.sh: $*" >&2; exit 1; }

# Main checkout of the folder (also from worktrees and subfolders); no git → the folder itself
main_dir() {
  local common
  if common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    (cd "$(dirname "$common")" && pwd -P)
  else
    (cd "$1" && pwd -P)
  fi
}

# owner/name of the origin of git folder $1 (https, ssh and scp-like URLs), else nothing
origin_repo() {
  local u; u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  u=${u%/}; u=${u%.git}
  awk -F'[/:]' 'NF >= 2 { print $(NF-1) "/" $NF }' <<<"$u"
}

# prop KEY: front matter property of the settings file, quotes stripped
prop() {
  awk -v k="$1" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t"\x27]+|[ \t"\x27]+$/, "", v); print v; exit }' "$settings" 2>/dev/null || true
}

# set_line KEY VALUE: one front matter line of the settings file; creates file and front matter when missing
set_line() {
  local key=$1 value=$2
  mkdir -p "$(dirname "$settings")"
  if [ "$(head -1 "$settings" 2>/dev/null)" != --- ]; then
    { printf -- '---\n---\n'; cat "$settings" 2>/dev/null || true; } > "$settings.tmp" && mv "$settings.tmp" "$settings"
  fi
  awk -v key="$key" -v line="$key: $value" '
    NR > 1 && !end && index($0, key ":") == 1 { print line; set = 1; next }
    NR > 1 && !end && $0 == "---" { if (!set) print line; end = 1 }
    { print }' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
}

usage="usage: board.sh create PROJECT_DIR [--owner OWNER] [--key KEY] | set PROJECT_DIR KEY VALUE"
cmd=${1:-}
case $cmd in
create)
  dir=${2:?$usage}; shift 2
  owner=; key=
  while [ $# -gt 0 ]; do
    case $1 in
      --owner) owner=${2:?--owner needs a value}; shift 2 ;;
      --key) key=${2:?--key needs a value}; shift 2 ;;
      *) die "create: unknown argument $1" ;;
    esac
  done
  dir=$(main_dir "$dir"); settings="$dir/.claude/project.md"
  # NFC, so a folder name with decomposed umlauts finds the Project titled with composed ones
  name=$(perl -CSA -MUnicode::Normalize -le 'print NFC shift' "$(basename "$dir")")
  repo=$(prop repo); [ -n "$repo" ] || repo=$(origin_repo "$dir")
  [ -n "$repo" ] || die "$dir has no origin: the board needs the code repo on GitHub"
  [ -n "$owner" ] || owner=$(prop owner)
  [ -n "$owner" ] || owner=${repo%%/*}
  [ -n "$key" ] || key=$(prop key)

  # titled: whether the Project's title carries the key (yes, no, or unknown when found by number)
  number=$(prop project); titled=unknown
  if [ -z "$number" ]; then
    # The owner's Projects titled <name> or <name> (<some key>), one per line: number TAB key
    found=$(gh project list --owner "$owner" -L 200 --format json | jq -r --arg n "$name" '
      .projects[]
      | (.title | if . == $n then "" elif startswith($n + " (") and endswith(")") then .[($n | length) + 2:-1] else null end) as $k
      | select($k != null) | "\(.number)\t\($k)"')
    if [ -n "$key" ]; then
      pick=$(awk -F'\t' -v k="$key" '$2 == k { print; exit }' <<<"$found")
      [ -n "$pick" ] || pick=$(awk -F'\t' '$2 == "" { print; exit }' <<<"$found")
    else
      pick=$(head -1 <<<"$found")
    fi
    if [ -z "$pick" ]; then
      number=$(gh project create --owner "$owner" --title "$name${key:+ ($key)}" --format json --jq .number)
      titled=yes
    else
      number=${pick%%$'\t'*}; titlekey=${pick#*$'\t'}
      [ -n "$key" ] || key=$titlekey
      [ "$titlekey" = "$key" ] && titled=yes || titled=no
    fi
  fi
  [ -n "$number" ] || die "no Project number from gh"
  # A key the title lacks, or a new key for a Project found by its number: the title gets it
  if [ -n "$key" ] && { [ $titled = no ] || { [ $titled = unknown ] && [ "$key" != "$(prop key)" ]; }; }; then
    gh project edit "$number" --owner "$owner" --title "$name ($key)" >/dev/null
  fi

  # Link Project -> code repo, unless the repo already lists the Project
  linked=$(gh api graphql -F owner="${repo%%/*}" -F name="${repo#*/}" -f query='
query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:100){nodes{number owner{... on User{login} ... on Organization{login}}}}}}' |
    jq -r --arg o "$owner" --arg n "$number" '
      [.data.repository.projectsV2.nodes[] | select((.number | tostring) == $n and (.owner.login | ascii_downcase) == ($o | ascii_downcase))] | length')
  [ "${linked:-0}" != 0 ] || gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null

  # --force makes an existing label a no-op update
  for l in urgent bug hotfix; do gh label create "$l" --repo "$repo" --force >/dev/null; done

  set_line board github
  set_line project "$number"
  [ -z "$key" ] || set_line key "$key"
  [ "$owner" = "${repo%%/*}" ] || set_line owner "$owner"
  echo "settings: $settings"; echo "repo: $repo"; echo "number: $number"; echo "owner: $owner"
  [ -z "$key" ] || echo "key: $key"
  ;;
set)
  dir=${2:?$usage}; key=${3:?missing KEY}; value=${4:?missing VALUE}
  dir=$(main_dir "$dir"); settings="$dir/.claude/project.md"
  set_line "$key" "$value"
  echo "saved: $key in $settings"
  ;;
*) echo "$usage" >&2; exit 2 ;;
esac
