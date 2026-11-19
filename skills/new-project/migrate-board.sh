#!/usr/bin/env bash
# One-off migration of a vault Kanban board to the project's GitHub board (spec: docs/github-boards-spec.md).
#   migrate-board.sh VAULT_BOARD_FILE PROJECT_DIR [--owner OWNER]
# Creates the board (board.sh create; OWNER as there), then one issue per card, lowest card number
# first. Each issue body starts with `was <KEY>-<n>` and holds the card's other lines, so Branch
# and PR lines stay as text. Columns: To do open; In progress open with Status In Progress;
# Done closed; any other column open with the column name as a label. Card tags become labels.
# `Needs:` ids become blocked-by links once every issue exists; an id that is not on this board
# stays text in the body and is reported. A card whose `was` line is already on an issue is not
# created again (its column rule is applied again, so a failed run can be repeated; In Progress
# only moves a card that is still Todo). When the run
# is complete the board file moves to <vault>/Archive/. The vault is VAULT, else two folders
# above the board file's folder (<vault>/Projects/<name>/<board file>).
# Needs gh, jq, and board.sh, tickets.sh and project.sh next to this script.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
die() { echo "migrate-board.sh: $*" >&2; exit 1; }

board=${1:?usage: migrate-board.sh VAULT_BOARD_FILE PROJECT_DIR [--owner OWNER]}
dir=${2:?usage: migrate-board.sh VAULT_BOARD_FILE PROJECT_DIR [--owner OWNER]}
shift 2
[ -f "$board" ] || die "no board file $board"
board=$(cd "$(dirname "$board")" && pwd -P)/$(basename "$board")
dir=$(cd "$dir" && pwd -P)
vault=${VAULT:-$(dirname "$(dirname "$(dirname "$board")")")}

bash "$here/board.sh" create "$dir" "$@" >/dev/null
cd "$dir"
tickets() { bash "$here/tickets.sh" "$@"; }
lookup=$(bash "$here/project.sh")
REPO=$(sed -n 's/^repo: //p' <<<"$lookup")
[ -n "$REPO" ] || die "project lookup has no repo after board.sh create"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/migrate-board.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

# Split the board: <tmp>/cards/<seq>.card holds a card's lines, <seq>.col its column
mkdir "$tmp/cards"
awk -v out="$tmp/cards" '
  /^%%/ { stop = 1 }
  stop { next }
  /^## / { col = substr($0, 4); card = ""; next }
  /^- \[[ xX]\] / { seq++; card = sprintf("%s/%04d", out, seq); print col > (card ".col"); close(card ".col"); print > (card ".card"); next }
  /^[ \t]/ { if (card != "") print > (card ".card"); next }
  { card = "" }' "$board"
cards=$(find "$tmp/cards" -name '*.card' | sort)
[ -n "$cards" ] || die "no cards in $board"

# Existing issues by `was` line: key, number, state. A rerun creates nothing twice.
gh issue list --repo "$REPO" --state all -L 1000 --json number,state,body |
  jq -r '.[] | (.body | split("\n")[0]) as $f | select($f | startswith("was ")) | "\($f[4:])\t\(.number)\t\(.state)"' > "$tmp/map"

# card_key FILE: <KEY>-<n> from "**KEY-n · Title**" or "**[[KEY-n Title]]**"
card_key() { sed -n '1s/^- \[[ xX]\] \*\*\(\[\[\)\{0,1\}\([A-Za-z0-9_]*-[0-9]*\).*/\2/p' "$1"; }

# Cards by their number, lowest first
for c in $cards; do
  k=$(card_key "$c"); [ -n "$k" ] || die "card without an id: $(head -1 "$c")"
  printf '%s\t%s\n' "${k##*-}" "$c"
done | sort -n -k1,1 -s | cut -f2 > "$tmp/order"

: > "$tmp/labels"   # labels made in this run
ensure_label() {
  grep -qxF -- "$1" "$tmp/labels" || { gh label create "$1" --repo "$REPO" --force >/dev/null; echo "$1" >> "$tmp/labels"; }
}

while IFS= read -r c; do
  key=$(card_key "$c")
  first=$(head -1 "$c")
  col=$(cat "${c%.card}.col")
  # Title and tags from the first line: "- [ ] **<head>** #tag #tag"
  heading=${first#*\*\*}; heading=${heading%%\*\**}
  rest=${first#*\*\*"$heading"\*\*}
  title=$(sed -e 's/^\[\[//; s/\]\]$//' -e "s/^$key \(· \)\{0,1\}//" <<<"$heading")
  [ -n "$title" ] || die "card $key has no title"
  labels=$(grep -o '#[^ ]*' <<<"$rest" | sed 's/^#//' | paste -sd, - || true)
  state=open; status=
  case $(tr '[:upper:] ' '[:lower:]-' <<<"$col") in
    to-do|todo) ;;
    in-progress) status=in-progress ;;
    done) state=done ;;
    *) labels=${labels:+$labels,}$col ;;
  esac
  existing=$(awk -F'\t' -v k="$key" '$1 == k { print $2 "\t" $3; exit }' "$tmp/map")
  if [ -n "$existing" ]; then
    n=${existing%%$'\t'*}; istate=${existing#*$'\t'}
    echo "kept $key as #$n"
  else
    IFS=, read -ra ls <<<"$labels"
    for l in ${ls[@]+"${ls[@]}"}; do ensure_label "$l"; done
    body=$(printf 'was %s\n' "$key"; tail -n +2 "$c" | sed 's/^	//')
    n=$(tickets create --title "$title" --body "$body" ${labels:+--label "$labels"})
    printf '%s\t%s\tOPEN\n' "$key" "$n" >> "$tmp/map"; istate=OPEN
    echo "created $key as #$n"
  fi
  # A kept card moves to In Progress only from Todo, so a card already Done is not pushed back
  if [ -n "$status" ]; then
    if [ -z "$existing" ] || [ "$(tickets show "$n" | jq -r .status)" = Todo ]; then
      tickets status "$n" "$status" >/dev/null
    fi
  fi
  if [ "$state" = done ] && [ "$istate" = OPEN ]; then
    tickets close "$n" --comment "Done on the vault board (was $key)." >/dev/null
  fi
done < "$tmp/order"

# Needs: -> blocked-by, now that every issue exists
while IFS= read -r c; do
  key=$(card_key "$c")
  n=$(awk -F'\t' -v k="$key" '$1 == k { print $2; exit }' "$tmp/map")
  needs=$(sed -n 's/^[ 	]*Needs:[ 	]*//p' "$c" | grep -o '[A-Za-z0-9_]*-[0-9][0-9]*' || true)
  [ -n "$needs" ] || continue
  have=$(tickets show "$n" | jq -r '.blockers[].ref')
  for need in $needs; do
    b=$(awk -F'\t' -v k="$need" '$1 == k { print $2; exit }' "$tmp/map")
    if [ -z "$b" ]; then echo "unresolved: $key needs $need, which is not on this board (left in the body)" >&2; continue; fi
    grep -qxF -- "$REPO#$b" <<<"$have" || tickets block "$n" "$b" >/dev/null
  done
done < "$tmp/order"

# Done: the vault board moves to <vault>/Archive
dest="$vault/Archive/$(basename "$board")"
[ ! -e "$dest" ] || die "$dest exists; board left in place"
mkdir -p "$vault/Archive"
mv "$board" "$dest"
echo "archived: $dest"
