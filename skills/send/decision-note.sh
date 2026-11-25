#!/usr/bin/env bash
# Writes a ticket's decision note into the brain: <vault>/raw/<Name>/<YYYY-MM-DD> <id> <title>.md.
#   decision-note.sh --ticket <ticket.md> --project <name> [--base <base>] [--close <reason>]
# <Name> is the page <vault>/wiki/projects/<Name>.md whose name matches <name>, ignoring case,
# spaces and hyphens. The note holds the ticket's `## Decisions` lines (`none` and template
# placeholder lines starting with `<` left out), on a close one more decision line
# `- Closed without code. Why: <reason>. Rejected: none.`, and, with --base and git in the current folder, the full text of every ADR (docs/adr/*.md)
# and every glossary entry (in a GLOSSARY.md) the branch added or changed against the merge
# base with origin/<base>.
# Every decision line carries the labels `Why:` and `Rejected:` (`Rejected: none` when the
# decision had no alternative).
# A note of the same ticket already in that folder (` <id> ` in its name) is overwritten.
# Prints `note: <path>`; `note: none` plus `reason:` when there is nothing to write (exit 0);
# `error: <cause>` when an argument is wrong, the title line is not `# <id>: <title>`, the
# vault or the project page is missing, or a decision line lacks a label: the error names the
# first such line, and no note is written (exit 1).
# Env: VAULT (the brain's folder).
set -u

err() { echo "error: $1"; exit 1; }

ticket= project= base= close=
while [ $# -gt 0 ]; do
  case $1 in --ticket|--project|--base|--close) [ $# -ge 2 ] || err "$1 needs a value" ;; esac
  case $1 in
    --ticket) ticket=$2 ;; --project) project=$2 ;; --base) base=$2 ;; --close) close=$2 ;;
    *) err "unknown argument $1" ;;
  esac
  shift 2
done

# NFC, lowercase, spaces and hyphens removed
norm() { perl -CSA -MUnicode::Normalize -le '$_ = lc NFC shift; s/[ -]//g; print' "$1"; }

[ -f "$ticket" ] || err "ticket file $ticket not found"
[ -n "${VAULT:-}" ] && [ -d "$VAULT/wiki/projects" ] || err "no vault with wiki/projects at '${VAULT:-}'"
name=
want=$(norm "$project")
for p in "$VAULT"/wiki/projects/*.md; do
  [ -f "$p" ] || continue
  n=$(basename "$p" .md)
  [ "$(norm "$n")" = "$want" ] && { name=$n; break; }
done
[ -n "$name" ] || err "no project page matches $project in $VAULT/wiki/projects"

# Title line `# <id>: <title>`
head=$(sed -n '1s/^# //p' "$ticket")
[[ $head == ?*": "?* ]] || err "the first line of $ticket is not '# <id>: <title>'"
id=${head%%: *} title=${head#*: }
ref=$(sed -n 's/^ref: //p' "$ticket" | head -1)

# The `## Decisions` section, without blank lines, `none` and template placeholders (`<...`)
decisions=$(awk '/^## / { on = ($0 == "## Decisions"); next } on && NF && tolower($0) != "none" && !/^</' "$ticket")
while IFS= read -r line; do
  [ -n "$line" ] || continue
  missing=
  [[ $line == *"Why:"* ]] || missing="Why:"
  [[ $line == *"Rejected:"* ]] || missing="${missing:+$missing and }Rejected:"
  [ -z "$missing" ] || err "decision line without $missing in $ticket: $line"
done <<<"$decisions"
[ -z "$close" ] || decisions=$(printf '%s\n%s' "$decisions" "- Closed without code. Why: ${close%.}. Rejected: none." | sed '/^$/d')

adrs= glossary=
if [ -n "$base" ] && top=$(git rev-parse --show-toplevel 2>/dev/null); then
  cd "$top" || err "cannot enter $top"
  mb=$(git merge-base "origin/$base" HEAD) || err "no merge base with origin/$base"
  changed=$( { git diff --name-only --diff-filter=AMR "$mb" --; git ls-files --others --exclude-standard; } | sort -u)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [[ $f =~ (^|/)docs/adr/[^/]+\.md$ ]]; then
      adrs+=$(printf '### `%s`\n\n%s\n\n' "$f" "$(cat "$f")")$'\n\n'
    elif [[ $f =~ (^|/)GLOSSARY\.md$ ]]; then
      # Changed lines of the current file: every line of a new file, else the hunks' new lines;
      # a pure deletion marks its line when it sits inside an entry (the next line is not blank).
      if git cat-file -e "$mb:$f" 2>/dev/null; then
        marks=$(git diff -U0 "$mb" -- "$f" | sed -n 's/^@@ [^+]*+\([0-9,]*\) @@.*/\1/p' | tr '\n' ' ')
      else
        marks=all
      fi
      entries=$(awk -v marks="$marks" '
        BEGIN { all = (marks == "all"); n = split(marks, m, " ")
          for (i = 1; i <= n; i++) { split(m[i], h, ","); c = h[2] == "" ? 1 : h[2] + 0
            if (c == 0) del[h[1] + 0] = 1; else for (j = 0; j < c; j++) hit[h[1] + j] = 1 } }
        { line[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (line[i] ~ /^\*\*[^*]+\*\*:/) { start = i; touched = 0
              for (k = i; k <= NR && (k == i || (line[k] != "" && line[k] !~ /^#/ && line[k] !~ /^\*\*[^*]+\*\*:/)); k++)
                if (all || hit[k] || (del[k] && line[k + 1] != "")) touched = 1
              if (touched) { for (j = start; j < k; j++) print line[j]; print "" }
              i = k - 1 } } }' "$f")
      [ -z "$entries" ] || glossary+=$(printf 'From `%s`:\n\n%s' "$f" "$entries")$'\n\n'
    fi
  done <<<"$changed"
fi

if [ -z "$decisions$adrs$glossary" ]; then
  echo "note: none"
  echo "reason: no decisions in $ticket and no ADR or glossary entry changed"
  exit 0
fi

today=$(date +%F)
# Characters a file name in the vault cannot hold are dropped
file_title=$(printf '%s' "$title" | tr -d '\\/:*?"<>|#^[]' | tr -s ' ')
dir="$VAULT/raw/$name"
file="$dir/$today $id $file_title.md"
# A rerun overwrites the ticket's earlier note, whatever its date
old=$(find "$dir" -maxdepth 1 -type f -name "* $id *.md" 2>/dev/null | head -1)
[ -z "$old" ] || file=$old
mkdir -p "$dir" || err "cannot create $dir"
{
  printf '# %s\n\n' "$head"
  printf 'Decisions of ticket %s in [[%s]], written by /send on %s.\n\n' "${ref:-$id}" "$name" "$today"
  [ -z "$decisions" ] || printf '## Decisions\n\n%s\n\n' "$decisions"
  [ -z "$adrs" ] || printf '## ADRs\n\n%s' "$adrs"
  [ -z "$glossary" ] || printf '## Glossary entries\n\n%s' "$glossary"
} | perl -0pe 's/\n+\z/\n/' > "$file" || err "cannot write $file"
echo "note: $file"
