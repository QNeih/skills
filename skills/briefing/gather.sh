#!/usr/bin/env bash
# Raw material for /briefing across every active project: Did, Next, Jira, Sentry, Dependabot, notes.
#   gather.sh            header lines, then `# Today` and one `# <project>` section per project with something to show
#   gather.sh --done N…  tick open notes N… (numbered as the briefing shows them) in <vault>/Briefing notes.md, print them
#   gather.sh --contacts  per active project `# <name>`, `client:`, one `contact:` line per `contacts` entry
#   gather.sh --add-contact <project> <entry>…  add confirmed entries to the note's `contacts`
# Env: VAULT, PROJECTS_ROOT (as for project.sh); BRIEFING_STATE (default ~/.claude/briefing),
# BRIEFING_TRANSCRIPTS (default ~/.claude/projects), BRIEFING_NOW (epoch seconds, default now; for tests).
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
[ -d "${VAULT:-}" ] || { echo "error: vault ${VAULT:-(VAULT not set)} not found"; exit 1; }
# macOS hides iCloud folders from a process without Full Disk Access: the glob below would just find no projects.
err=$(ls "$VAULT/Projects" 2>&1 >/dev/null) || { echo "error: can't read the vault: $err"; exit 1; }
notes_file="$VAULT/Briefing notes.md"

# --done N...: numbers as the briefing showed them; resolve all to file lines before ticking any
if [ "${1:-}" = --done ]; then
  shift; lines=
  for n in "$@"; do
    l=$(grep -n '^- \[ \] ' "$notes_file" 2>/dev/null | sed -n "${n}p" | cut -d: -f1)
    [ -n "$l" ] || { echo "error: no open note $n"; exit 1; }
    lines+=" $l"
  done
  for l in $lines; do perl -i -pe "s/^- \\[ \\] /- [x] / if \$. == $l" "$notes_file"; sed -n "${l}p" "$notes_file"; done
  exit 0
fi

state=${BRIEFING_STATE:-$HOME/.claude/briefing}
tx=${BRIEFING_TRANSCRIPTS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}
now=${BRIEFING_NOW:-$(date +%s)}
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT

# --- dates (local time) ---
fmt() { perl -MPOSIX -e 'print strftime($ARGV[1], localtime $ARGV[0])' "$1" "$2"; }
midnight() { perl -MPOSIX -e 'my ($y, $m, $d) = split /-/, shift; print mktime(0, 0, 0, $d, $m - 1, $y - 1900)' "$1"; }
# Latest Mon–Fri before $1 among the dates on stdin; none → the weekday before $1
last_workday() {
  perl -MTime::Local -e '
    my $t = shift; my $best;
    sub wd { my ($y, $m, $d) = split /-/, shift; (gmtime timegm(0, 0, 12, $d, $m - 1, $y))[6] }
    while (<STDIN>) { chomp; next unless /^\d{4}-\d\d-\d\d$/ && $_ lt $t && wd($_) % 6;
      $best = $_ if !defined $best || $_ gt $best }
    unless ($best) { my ($y, $m, $d) = split /-/, $t; my $e = timegm(0, 0, 12, $d, $m - 1, $y);
      do { $e -= 86400 } until (gmtime $e)[6] % 6;
      my @g = gmtime $e; $best = sprintf "%04d-%02d-%02d", $g[5] + 1900, $g[4] + 1, $g[3] }
    print $best' "$1"
}
today=$(fmt "$now" %F)

# --- projects: notes tagged project, status not done/archived ---
front() { awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1' "$1"; }
prop() { front "$1" | awk -v k="$2" 'index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t"\x27]+|[ \t"\x27]+$/, "", v); print v; exit }'; }
is_project() {
  front "$1" | awk '/^tags:/ { t = 1; if ($0 ~ /[\[ ,]project([\], ]|$)/) f = 1; next }
    t && /^[ \t]*- *project[ \t]*$/ { f = 1 } /^[^ \t-]/ { t = 0 } END { exit !f }'
}
# active: <name>\t<note> per active project
active() {
  for d in "$VAULT"/Projects/*/; do
    d=${d%/}; n=$d/${d##*/}.md
    [ -f "$n" ] && is_project "$n" || continue
    case "$(prop "$n" status)" in done|archived) continue ;; esac
    printf '%s\t%s\n' "${d##*/}" "$n"
  done
}
# contacts <note>: one entry per line, from a block (`- a`) or inline (`[a, b]`) list; quotes stripped
contacts() {
  front "$1" | awk '
    function out(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v) }
      else if (v ~ /^\x27.*\x27$/) v = substr(v, 2, length(v) - 2)
      if (v != "") print v }
    /^contacts:/ { c = 1; v = substr($0, 10); if (v ~ /\[/) { gsub(/^[ \t]*\[|\][ \t]*$/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) out(a[i]) } next }
    c && /^[ \t]*- / { sub(/^[ \t]*- /, ""); out($0); next }
    /^[^ \t]/ { c = 0 }'
}

# --contacts: per active project `# <name>`, `client:` and one `contact:` line per entry
if [ "${1:-}" = --contacts ]; then
  active | while IFS=$'\t' read -r name n; do
    echo "# $name"
    c=$(prop "$n" client); [ -z "$c" ] || echo "client: $c"
    contacts "$n" | sed 's/^/contact: /'
  done
  exit 0
fi

# --add-contact <project> <entry>...: add entries Quinn confirmed to the note's `contacts` (block list, quoted)
if [ "${1:-}" = --add-contact ]; then
  n=$(active | awk -F'\t' -v p="$2" '$1 == p { print $2 }')
  [ -n "$n" ] || { echo "error: no active project $2"; exit 1; }
  contacts "$n" > "$tmp/all"; added=
  for e in "${@:3}"; do
    grep -qixF -- "$e" "$tmp/all" || { echo "$e" >> "$tmp/all"; added+=", $e"; }
  done
  [ -n "$added" ] || { echo "contacts $2: nothing new"; exit 0; }
  # drop the old contacts key, write the whole list before the closing ---
  awk -v list="$tmp/all" 'NR == 1 { fm = ($0 == "---"); print; next }
    fm && /^---$/ { print "contacts:"; while ((getline e < list) > 0) { gsub(/"/, "\\\"", e); print "  - \"" e "\"" }
      fm = 0; print; next }
    fm && /^contacts:/ { c = 1; next } fm && c && /^[ \t]*- / { next } { c = 0; print }' "$n" > "$tmp/note" &&
    cat "$tmp/note" > "$n"
  echo "contacts $2: added ${added#, }"
  exit 0
fi

# lookup output per project in $tmp/look.<i>; a folder the lookup can't pin down → $tmp/folder.<i>
# (no folder at all is a vault-only project: silent)
i=0
active | while IFS=$'\t' read -r name n; do
  i=$((i + 1))
  "$here/project.sh" --note "$name" </dev/null > "$tmp/look.$i"
  dir=$(sed -n 's/^dir: //p' "$tmp/look.$i")
  fix="— set local: <folder> in the project note"
  if [ "$dir" = none ]; then
    sed -n "s/^reason: \(two clones .*\)/error: folder: \1 $fix/p" "$tmp/look.$i" > "$tmp/folder.$i"; dir=
  elif [ ! -d "$dir" ]; then
    echo "error: folder: $dir not found $fix" > "$tmp/folder.$i"; dir=
  fi
  printf '%s\t%s\t%s\n' "$name" "$n" "$dir"
done > "$tmp/projects"
active=$(cut -f1 "$tmp/projects")

# --- prompts and commits per project (45 days), files $tmp/p.<i> and $tmp/c.<i> ---
enc() { sed 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
awk -F'\t' '$3 != "" { print NR "\t" $3 }' "$tmp/projects" | while IFS=$'\t' read -r i dir; do
  printf '%s\t%s\n' "$(enc "$dir")" "$i"
done > "$tmp/encs"
# Each transcript dir belongs to the project with the longest encoded folder that it equals or starts with + `-`
# (worktree sessions: <folder>--claude-worktrees-…); so acme-two's sessions don't count for acme.
ls "$tx" 2>/dev/null | awk -F'\t' 'NR == FNR { e[$1] = $2; next }
  { b = ""; for (k in e) if (($0 == k || index($0, k "-") == 1) && length(k) > length(b)) b = k
    if (b != "") print e[b] "\t" $0 }' "$tmp/encs" - > "$tmp/txdirs"
localtime='(sub("\\.[0-9]+Z$"; "Z") | fromdate | strflocaltime("%Y-%m-%d %H:%M"))'
since45=$(fmt $((now - 45 * 86400)) '%F %T')
while IFS=$'\t' read -r i tdir; do
  find "$tx/$tdir" -maxdepth 1 -name '*.jsonl' -mtime -45 -print0 | xargs -0 cat | jq -r "
    select(.type == \"user\" and .isSidechain != true and (.message.content | type) == \"string\"
      and (.message.content | startswith(\"<\") | not))
    | \"\(.timestamp | $localtime) \(.message.content | gsub(\"\\\\s+\"; \" \") | .[0:160])\"" 2>/dev/null >> "$tmp/p.$i"
done < "$tmp/txdirs"
i=0
while IFS=$'\t' read -r name note dir <&3; do
  i=$((i + 1))
  [ -n "$dir" ] && git -C "$dir" rev-parse 2>/dev/null || continue
  me=$(git -C "$dir" config user.email) || continue
  git -C "$dir" log --all --author="$me" --since="$since45" --until="$(fmt "$now" '%F %T')" \
    --date=format-local:'%F %H:%M' --format='%ad %s' > "$tmp/c.$i"
done 3< "$tmp/projects"

last=$(cat "$tmp"/p.* "$tmp"/c.* 2>/dev/null | cut -c1-10 | last_workday "$today")
echo "today: $(fmt "$now" '%F %a')"
echo "last workday: $(fmt "$(midnight "$last")" '%F %a')"
# New items since the last run; first run → last workday 00:00. A later run the same day skips Did.
did=1
if [ -f "$state/last-run" ]; then
  since=$(cat "$state/last-run")
  echo "since: $(fmt "$since" '%F %H:%M')"
  [ "$(fmt "$since" %F)" = "$today" ] && { did=; echo "later run today: no Did"; }
else
  since=$(midnight "$last")
  echo "since: $(fmt "$since" '%F %H:%M') (first run)"
fi
# Did window: last workday through yesterday
in_did() { awk -v a="$last" -v b="$today" 'substr($0, 1, 10) >= a && substr($0, 1, 10) < b' "$@" 2>/dev/null | sort; }

# --- notes: open `- [ ]` lines, numbered in file order ---
[ -f "$notes_file" ] && grep '^- \[ \] ' "$notes_file" | awk '{ sub(/^- \[ \] /, ""); print ++n "\t" $0 }' > "$tmp/notes"
touch "$tmp/notes"
today_lines=
while IFS=$'\t' read -r n text; do
  link=$(grep -oE '\[\[[^]]+\]\]$' <<<"$text" | tr -d '[]')
  if [ -z "$link" ] || ! grep -qxF "$link" <<<"$active"; then today_lines+="note $n: $text"$'\n'; fi
done < "$tmp/notes"

# --- Installed packages changed since $since, from the hourly claude-config backup ---
cfg="$PROJECTS_ROOT/claude-config"
# <kind> <path in repo> <jq filter: object name → version>; prints `<kind> <name>: added|removed|<old> → <new>`
pkg_changes() {
  local old new
  old=$(git -C "$cfg" show "$base:$2" 2>/dev/null) || return 0 # not backed up yet at $base: no baseline to compare
  new=$(git -C "$cfg" show "HEAD:$2" 2>/dev/null) || new='{}'
  jq -rn --arg kind "$1" --argjson o "$old" --argjson n "$new" "
    def f: $3;
    (\$o | f) as \$a | (\$n | f) as \$b | ([\$a, \$b] | add | keys[]) as \$k | select(\$a[\$k] != \$b[\$k])
    | \"\(\$kind) \(\$k): \" + if \$a[\$k] == null then \"added\" elif \$b[\$k] == null then \"removed\"
      elif \$kind == \"skill\" then \"updated\" else \"\(\$a[\$k]) → \(\$b[\$k])\" end"
}
if [ -d "$cfg/.git" ] && base=$(git -C "$cfg" rev-list -1 --before="@$since" HEAD) && [ -n "$base" ]; then
  pkg=$(pkg_changes skill agents/.skill-lock.json '.skills // {} | map_values(.skillFolderHash)'
    pkg_changes plugin claude/plugins/installed_plugins.json '.plugins // {} | map_values(.[0].version)')
  [ -z "$pkg" ] || today_lines+="$pkg"$'\n'
fi
[ -z "$today_lines" ] || printf '# Today\n%s' "$today_lines"

# --- Next on a vault board: cards in In progress; none → first #urgent card in To do, else the first ---
# Each card carries its goal in one sentence: its `Goal:`/`Ziel:` line, else the first sentence of its
# first description line (meta lines Branch/PR/Braucht/Needs skipped). Same rule as dashboard/server.py.
vault_next() {
  awk 'function flush() { if (c == "") return; g = goal != "" ? goal : first; t = c (g != "" ? " — " g : "")
      if (col == "in progress") ip = ip "next: " t " (in progress)\n"
      else if (col == "to do") { if (!fst) fst = t; if (!urgent && c ~ /#urgent/) urgent = t }
      c = "" }
    /^## / { flush(); col = tolower(substr($0, 4)); next }
    /^- \[[ x]\] / { flush(); c = substr($0, 7); gsub(/\*\*/, "", c); goal = first = ""; next }
    c != "" && /^\t/ { l = substr($0, 2)
      if (l ~ /^(Goal|Ziel):/) { sub(/^(Goal|Ziel):[ \t]*/, "", l); goal = l }
      else if (first == "" && l !~ /^(Branch|PR|Braucht|Needs)[ :]/) { first = l; if (match(first, /[.!?][ \t]/)) first = substr(first, 1, RSTART) }
      next }
    { flush() }
    END { flush(); if (ip) printf "%s", ip; else if (urgent || fst) print "next: " (urgent ? urgent : fst) " (to do)" }' "$1"
}

# need <cli> <source> <name>: a missing CLI is one line with its fix
need() { command -v "$1" >/dev/null || { echo "error: $2: $1 not installed — install the $3 ($1)"; return 1; }; }

# --- Vault board: a card outside Done whose `PR <github url>` line is merged moves to the end of Done, ticked.
# Catches PRs opened without /send (which moves the card itself). ---
vault_merged() {
  local id url st ids=
  while IFS=$'\t' read -r id url; do
    need gh Board "GitHub CLI" || return
    st=$(gh pr view "$url" --json state -q .state 2>&1) || { echo "error: Board: $(head -1 <<<"$st") — gh auth login"; continue; }
    [ "$st" = MERGED ] || continue
    grep -qiE '^## +done[[:space:]]*$' "$1" || { echo "error: Board: no Done column on $1"; return; }
    ids+="$id"$'\n'; echo "moved: $id to Done (PR #${url##*/} merged)"
  done < <(awk '/^## / { c = tolower(substr($0, 4)); sub(/[ \t]+$/, "", c); out = c == "done"; id = ""; next }
      /^- \[[ x]\] / { id = ""; if (!out && match($0, /\*\*[A-Z][A-Z0-9]*-[0-9]+ /)) id = substr($0, RSTART + 2, RLENGTH - 3); next }
      id != "" && /^\tPR https:\/\/github\.com\// { print id "\t" substr($0, 5); id = "" }' "$1")
  [ -n "$ids" ] || return 0
  IDS=$ids perl -0777 -i -pe '
    my %want = map { $_ => 1 } split /\n/, $ENV{IDS};
    my @l = split /^/m; my (@keep, @moved, $col);
    for (my $i = 0; $i < @l; $i++) {
      if ($l[$i] =~ /^## +(.*?)\s*$/) { $col = lc $1 }
      if (($col // "") ne "done" && $l[$i] =~ /^- \[[ x]\] \*\*([A-Z][A-Z0-9]*-\d+) / && $want{$1}) {
        push @moved, $l[$i] =~ s/^- \[ \]/- [x]/r;
        push @moved, $l[++$i] while $i + 1 < @l && $l[$i + 1] =~ /^\t/;
        next;
      }
      push @keep, $l[$i];
    }
    my ($d) = grep { $keep[$_] =~ /^## +done\s*$/i } 0 .. $#keep;
    my $e = $d + 1; $e++ while $e < @keep && $keep[$e] !~ /^(## |%% kanban:settings)/;
    $e-- while $e > $d + 1 && $keep[$e - 1] =~ /^\s*$/;
    $keep[$e - 1] .= "\n" unless $keep[$e - 1] =~ /\n$/;
    splice @keep, $e, 0, @moved;
    $_ = join "", @keep' "$1"
}

# --- Jira (acli): open sprint of key $1 diffed against the snapshot of the last run; Next ---
# acli missing or logged out: one line per run, in the first section that needs Jira (a key may be commit noise)
jira() {
  local snap="$state/jira-$1.json" raw new
  [ -n "$1" ] || return 0
  if [ -z "${jira_me+x}" ]; then
    jira_me=
    if need acli Jira "Atlassian CLI"; then
      if raw=$(acli jira auth status 2>&1); then
        jira_me=$(sed -n 's/^ *Email: *//p' <<<"$raw")
        [ -n "$jira_me" ] || echo "error: Jira: acli jira auth status shows no email — acli jira auth login"
      else echo "error: Jira: $(head -1 <<<"$raw") — acli jira auth login"; fi
    fi
  fi
  [ -n "$jira_me" ] || return
  raw=$(acli jira workitem search --jql "project = $1 AND sprint in openSprints() ORDER BY updated DESC" \
    --fields key,summary,status,assignee,priority,issuetype,labels --json --paginate 2>&1) || {
    # a key Jira doesn't know (UTF-8, SHA-256 in commits) is not a Jira board
    grep -q "does not exist for the field 'project'" <<<"$raw" || echo "error: Jira: $(head -1 <<<"$raw") — acli jira auth login"
    return; }
  new=$(jq --arg me "$jira_me" '[.[] | {key, summary: .fields.summary, status: .fields.status.name,
    cat: .fields.status.statusCategory.key, assignee: (.fields.assignee.displayName // "unassigned"),
    you: (.fields.assignee.emailAddress == $me), type: .fields.issuetype.name, prio: .fields.priority.id,
    labels: (.fields.labels // [])}]' <<<"$raw" 2>/dev/null) || { echo "error: Jira: unexpected acli output — update acli"; return; }
  # ponytail: snapshot diff, misses a move undone between two runs
  [ -f "$snap" ] && jq -r --slurpfile old "$snap" '
    ($old[0] | map({(.key): .}) | add // {}) as $o
    | .[] | $o[.key] as $p | "\(.assignee)\(if .you then " (you)" else "" end) — \(.summary)" as $tail
    | if $p == null then "jira added: \(.key) [\(.status)] \($tail)"
      elif $p.status != .status and $p.cat != "new" and (.cat == "new" or (.status | ascii_downcase) == "in progress")
      then "jira back: \(.key) \($p.status) → \(.status) \($tail)" else empty end' <<<"$new"
  # Next: my tickets in In progress; none → the one /work would pick (hotfix, priority, type, status; JQL order breaks ties)
  jq -r 'def bucket: (.type // "" | ascii_downcase) as $t
      | if $t | IN("bug", "defect", "bugfix", "sub-bug") then 0 elif $t | IN("story", "user story") then 1
        elif $t == "epic" then 2 elif $t == "task" then 3 elif $t | IN("spike", "research", "investigation") then 4 else 5 end;
    [.[] | select(.you and .cat != "done")] as $mine
    | [$mine[] | select((.status | ascii_downcase) == "in progress")] as $ip
    | if $ip != [] then $ip[] | "next: \(.key) \(.summary) (in progress)"
      elif $mine != [] then $mine | sort_by([(if [.summary, .type] + .labels | join(" ") | test("hotfix"; "i") then 0 else 1 end),
        (.prio // "99" | tonumber), bucket, (if .cat == "indeterminate" then 0 else 1 end)]) | .[0]
        | "next: \(.key) \(.summary) (top pick)"
      else empty end' <<<"$new"
  mkdir -p "$state" && printf '%s' "$new" > "$snap"
}

# --- Sentry: projects from committed DSNs (or the note's `sentry`), staging if present; new/regressed since $since ---
sentry_lines() {
  local out sp env q list
  out=$("$here/sentry-projects.sh" "$1" "$2")
  if grep -qx 'sentry: none' <<<"$out"; then
    # no DSN, no git, or only DSNs outside Quinn's Sentry organizations: Sentry isn't set up here
    grep -qE '^reason: (no Sentry DSN committed|no committed DSN belongs|.* is not a git repo)' <<<"$out" && return
    need sentry Sentry "Sentry CLI" && echo "error: Sentry: $(sed -n 's/^reason: //p' <<<"$out") — sentry auth login"
    return
  fi
  need sentry Sentry "Sentry CLI" || return
  for sp in $(sed -n 's/^sentry: //p' <<<"$out"); do
    env=$(sentry api "projects/$sp/environments/" 2>&1) || { echo "error: Sentry: $(head -1 <<<"$env") — sentry auth login"; continue; }
    jq -e 'any(.[]; .name == "staging")' <<<"$env" >/dev/null 2>&1 && env=staging || env=
    q="is:unresolved level:error${env:+ environment:$env}"
    list=$(sentry issue list "$sp" --query "$q" --limit 100 --json --fields shortId,title,count,firstSeen,lastSeen,substatus 2>&1) ||
      { echo "error: Sentry: $(head -1 <<<"$list") — sentry auth login"; continue; }
    jq -r --arg p "$sp${env:+ $env}" --argjson since "$since" '
      def epoch: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate;
      (if type == "object" then .data else . end) as $i
      | [$i[] | select((.firstSeen | epoch) >= $since) | .shortId] as $new
      | ([$i[] | select(.substatus == "regressed" and (.lastSeen | epoch) >= $since) | .shortId] - $new) as $reg
      | select($new + $reg != [])
      | "sentry \($p): \($i | length) issues"
        + (if $new != [] then ", new: \($new | join(" "))" else "" end)
        + (if $reg != [] then ", regressed: \($reg | join(" "))" else "" end)' <<<"$list" 2>/dev/null ||
      echo "error: Sentry: unexpected output of sentry issue list — update the sentry CLI"
  done
}

# --- Dependabot: open PRs of a GitHub repo, new since $since ---
dependabot_lines() {
  local repo list
  repo=$(prop "$1" repo); [ -n "$repo" ] || [ -z "$2" ] || repo=$(git -C "$2" remote get-url origin 2>/dev/null)
  repo=$(sed -nE 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' <<<"${repo%/}"); repo=${repo%.git}
  [ -n "$repo" ] || return 0
  need gh Dependabot "GitHub CLI" || return
  list=$(gh pr list -R "$repo" --author app/dependabot --state open --json number,title,createdAt 2>&1) ||
    { echo "error: Dependabot: $(head -1 <<<"$list") — gh auth login"; return; }
  jq -r --argjson since "$since" '[.[] | select((.createdAt | fromdate) >= $since)] as $new | select($new != [])
    | "dependabot: \($new | length) new of \(length) open: \($new | map("#\(.number) \(.title)") | join("; "))"' <<<"$list"
}

# --- one section per project with something to show (fd 3, so no CLI eats the list from stdin) ---
i=0
while IFS=$'\t' read -r name note dir <&3; do
  i=$((i + 1))
  {
    if [ -n "$did" ]; then
      in_did "$tmp/p.$i" | sed 's/^/prompt /'
      in_did "$tmp/c.$i" | sed 's/^/commit /'
      if [ -n "$dir" ] && git -C "$dir" rev-parse 2>/dev/null; then
        n=$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')
        case $n in 0) s=clean ;; 1) s="uncommitted (1 file)" ;; *) s="uncommitted ($n files)" ;; esac
        b=$(git -C "$dir" branch --show-current)
        echo "left off: ${b:-detached HEAD}, $s"
      fi
    fi
    board=$(sed -n 's/^board: //p' "$tmp/look.$i"); key=$(sed -n 's/^key: //p' "$tmp/look.$i")
    case "$board" in
      vault) bf=$(sed -n 's/^board-file: //p' "$tmp/look.$i"); vault_merged "$bf"; vault_next "$bf" ;;
      jira-candidate) jira "$key" ;;
      *atlassian.net*) jira "$(grep -oE '(projects|browse)/[A-Z][A-Z0-9]+' <<<"$board" | head -1 | cut -d/ -f2)" ;;
    esac
    cat "$tmp/folder.$i" 2>/dev/null
    [ -z "$dir" ] || sentry_lines "$dir" "$note"
    dependabot_lines "$note" "$dir"
    while IFS=$'\t' read -r n text; do
      case "$text" in *" [[$name]]") echo "note $n: ${text% \[\[$name\]\]}" ;; esac
    done < "$tmp/notes"
  } > "$tmp/out"
  # left off alone is nothing to show
  grep -qv '^left off:' "$tmp/out" && { echo "# $name"; cat "$tmp/out"; }
done 3< "$tmp/projects"

mkdir -p "$state" && echo "$now" > "$state/last-run"
