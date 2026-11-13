#!/usr/bin/env bash
# /briefing gather step (skills/briefing/gather.sh) against a fixture vault, repos, transcripts and state dir.
# sentry, gh and acli are stubs on PATH; no live service is called.
. "$(dirname "$0")/lib.sh"
GATHER="$REPO_DIR/skills/briefing/gather.sh"
fixture_new
export BRIEFING_STATE="$FIX/state" BRIEFING_TRANSCRIPTS="$FIX/transcripts" GIT_CONFIG_GLOBAL="$FIX/gitconfig" TZ=Europe/Berlin
printf '[user]\n\temail = q@acme.test\n\tname = Q\n' > "$GIT_CONFIG_GLOBAL"
mkdir -p "$FIX/bin" "$BRIEFING_TRANSCRIPTS"
export PATH="$FIX/bin:$PATH" FIX
# Stubs: <cli> runs $FIX/stub/<cli>.sh with its args (missing → exit 3); <CLI>_FAIL=<msg> makes it fail with msg.
for cli in sentry gh acli; do
  cat > "$FIX/bin/$cli" <<STUB
#!/usr/bin/env bash
echo "$cli \$*" >> "\$FIX/calls"
fail=\${$(tr a-z A-Z <<<"$cli")_FAIL:-}
[ -n "\$fail" ] && { echo "\$fail" >&2; exit 1; }
[ -f "\$FIX/stub/$cli.sh" ] && exec bash "\$FIX/stub/$cli.sh" "\$@"
exit 3
STUB
  chmod +x "$FIX/bin/$cli"
done
mkdir -p "$FIX/stub"

# Monday 2026-11-09 09:00 local
at() { perl -MPOSIX -e 'my ($y,$m,$d,$H,$M) = split /\D/, shift; print mktime(0,$M,$H,$d,$m-1,$y-1900)' "$1"; }
NOW=$(at "2026-11-09 09:00")
gather() { BRIEFING_NOW=${2:-$NOW} "$GATHER" "${@:3}" 2>&1; }
# section <name> <output>: lines of one `# <name>` section
section() { awk -v h="# $1" '$0 == h { on = 1; next } /^# / { on = 0 } on' <<<"$2"; }

# --- Projects: tagged project, status not done/archived; nothing to show → no section ---
fixture_note Acme
fixture_note Old "status: done"
fixture_note Gone "status: archived"
fixture_note Quiet
mkdir -p "$VAULT/Projects/Recipe"; printf -- '---\ntags: [cooking]\n---\n' > "$VAULT/Projects/Recipe/Recipe.md"
cat > "$VAULT/Briefing notes.md" <<'MD'
- [ ] 2026-11-05 call the tax office
- [x] 2026-11-05 already done [[Acme]]
- [ ] 2026-11-06 send the offer [[Acme]]
- [ ] 2026-11-06 old thing [[Old]]
- [ ] 2026-11-06 cook [[Recipe]]
MD
out=$(gather)
s=$(section Acme "$out")
expect "notes: project note under its project, numbered among open notes" "$s" "note 2: 2026-11-06 send the offer"
grep -q 'already done' <<<"$out" && fail "notes: ticked note left out" || pass "notes: ticked note left out"
t=$(section Today "$out")
expect "notes: note without project under Today" "$t" "note 1: 2026-11-05 call the tax office"
expect "notes: note of an inactive project under Today" "$t" "note 3: 2026-11-06 old thing [[Old]]"
expect "notes: note of a non-project note under Today" "$t" "note 4: 2026-11-06 cook [[Recipe]]"
for p in Old Gone Quiet Recipe; do
  grep -qx "# $p" <<<"$out" && fail "no section: $p" || pass "no section: $p"
done

# --done ticks the n-th open note
out=$(gather "" "" --done 2)
expect "done: prints the ticked line" "$out" "- [x] 2026-11-06 send the offer [[Acme]]"
grep -q 'send the offer' <<<"$(section Acme "$(gather)")" && fail "done: note leaves the briefing" || pass "done: note leaves the briefing"
expect "done: unknown number" "$(gather "" "" --done 9)" "error: no open note 9"
printf -- '- [ ] 2026-11-07 a\n- [ ] 2026-11-07 b\n- [ ] 2026-11-07 c\n' >> "$VAULT/Briefing notes.md"
out=$(gather "" "" --done 4 6)
expect "done several: first" "$out" "- [x] 2026-11-07 a"
expect "done several: numbers refer to the briefing, not shifted" "$out" "- [x] 2026-11-07 c"
grep -q '^- \[ \] 2026-11-07 b' "$VAULT/Briefing notes.md" && pass "done several: others stay open" || fail "done several: others stay open"
perl -i -ne 'print unless /2026-11-07 [abc]/' "$VAULT/Briefing notes.md"
rm -rf "$BRIEFING_STATE"

# --- Did: last workday from prompts and commits, worktree transcripts, left off ---
enc() { sed 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
# prompt <folder> <UTC timestamp> <text> [session dir suffix]
prompt() {
  local d="$BRIEFING_TRANSCRIPTS/$(enc "$1")${4:-}"; mkdir -p "$d"
  jq -nc --arg t "$2" --arg c "$3" '{type: "user", timestamp: $t, message: {content: $c}}' >> "$d/s1.jsonl"
}
# commit <repo> <local date> <subject> [author email]
commit() {
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.email="${4:-q@acme.test}" commit -q --allow-empty -m "$3"
}
A="$PROJECTS_ROOT/acme"
fixture_repo "$A"
prompt "$A" 2026-11-06T13:03:00.000Z "fix the login"
jq -nc '{type: "user", timestamp: "2026-11-06T13:05:00Z", isSidechain: true, message: {content: "subagent prompt"}}' >> "$BRIEFING_TRANSCRIPTS/$(enc "$A")/s1.jsonl"
jq -nc '{type: "user", timestamp: "2026-11-06T13:06:00Z", message: {content: "<command-name>/clear</command-name>"}}' >> "$BRIEFING_TRANSCRIPTS/$(enc "$A")/s1.jsonl"
prompt "$A" 2026-11-07T09:00:00Z "weekend idea" "--claude-worktrees-wt1"
prompt "$A" 2026-11-02T09:00:00Z "older prompt"
commit "$A" "2026-11-06 15:00" "Add login"
commit "$A" "2026-11-06 16:00" "Someone else's work" other@acme.test
git -C "$A" checkout -q -b feature/x; commit "$A" "2026-11-06 17:00" "Branch work"
touch "$A/dirty.txt"
fixture_note "Acme Two"; mkdir -p "$PROJECTS_ROOT/acme-two"
prompt "$PROJECTS_ROOT/acme-two" 2026-11-06T10:00:00Z "two prompt"
out=$(gather)
expect "header: today" "$out" "today: 2026-11-09 Mon"
expect "header: last workday skips the weekend" "$out" "last workday: 2026-11-06 Fri"
expect "header: first run since last workday 00:00" "$out" "since: 2026-11-06 00:00 (first run)"
s=$(section Acme "$out")
expect "did: prompt in local time" "$s" "prompt 2026-11-06 14:03 fix the login"
expect "did: worktree session prompt, weekend in the window" "$s" "prompt 2026-11-07 10:00 weekend idea"
expect "did: commit" "$s" "commit 2026-11-06 15:00 Add login"
expect "did: commit on another branch" "$s" "commit 2026-11-06 17:00 Branch work"
expect "did: left off" "$s" "left off: feature/x, uncommitted (1 file)"
for x in "subagent prompt" "/clear" "older prompt" "Someone else" "two prompt"; do
  grep -qF "$x" <<<"$s" && fail "did: left out: $x" || pass "did: left out: $x"
done
expect "did: prefix-sharing folder gets its own prompts" "$(section "Acme Two" "$out")" "prompt 2026-11-06 11:00 two prompt"

# A later run the same day: since = last run, no Did
out=$(gather "" "$(at "2026-11-09 11:30")")
expect "later run: since last run" "$out" "since: 2026-11-09 09:00"
expect "later run: says so" "$out" "later run today: no Did"
grep -qE '^(prompt|commit|left off)' <<<"$out" && fail "later run: no Did" || pass "later run: no Did"
# Next day: Did again, since the last run
prompt "$A" 2026-11-09T10:00:00Z "monday work"
out=$(gather "" "$(at "2026-11-10 08:00")")
expect "next day: last workday" "$out" "last workday: 2026-11-09 Mon"
expect "next day: since last run" "$out" "since: 2026-11-09 11:30"

# No activity → the previous weekday
out=$(BRIEFING_STATE="$FIX/state2" gather "" "$(at "2026-11-02 08:00")")
expect "no activity: previous weekday" "$out" "last workday: 2026-10-30 Fri"

# --- Next: vault board ---
rm -rf "$BRIEFING_STATE"
board="$VAULT/Projects/Acme/Acme Board.md"
cat > "$board" <<'MD'
---
kanban-plugin: board
---

## To do

- [ ] **ACM-1 · First card**
	Branch `x`
- [ ] **ACM-2 · Urgent card** #urgent
- [ ] **ACM-3 · Later urgent** #urgent

## In Progress


## Done

- [x] **ACM-0 · Old card**
MD
expect "next: vault, #urgent first" "$(section Acme "$(gather)")" "next: ACM-2 · Urgent card #urgent (to do)"
perl -0 -i -pe 's/## In Progress\n\n/## In Progress\n\n- [ ] **ACM-5 · Working on it**\n- [ ] **ACM-6 · And this**\n/' "$board"
rm -rf "$BRIEFING_STATE"
s=$(section Acme "$(gather)")
expect "next: vault, in progress first" "$s" "next: ACM-5 · Working on it (in progress)"
expect "next: vault, every in-progress card" "$s" "next: ACM-6 · And this (in progress)"
grep -q 'ACM-2' <<<"$s" && fail "next: no to-do pick when in progress" || pass "next: no to-do pick when in progress"
fixture_note Cards; mkdir -p "$VAULT/Projects/Cards"
printf '## To do\n\n- [ ] **CRD-1 · Only card**\n' > "$VAULT/Projects/Cards/Cards Board.md"
expect "next: vault board without a folder" "$(section Cards "$(gather "" "$(at "2026-11-09 12:00")")")" "next: CRD-1 · Only card (to do)"
printf '## To do\n\n- [ ] **CRD-1 · Only card**\n\tSave reports. Then share.\n\tBraucht: nichts\n' > "$VAULT/Projects/Cards/Cards Board.md"
expect "next: goal is the first sentence" "$(section Cards "$(gather "" "$(at "2026-11-09 12:00")")")" "next: CRD-1 · Only card — Save reports. (to do)"
printf '## To do\n\n- [ ] **CRD-1 · Only card**\n\tLong text. More.\n\tZiel: Ship it\n' > "$VAULT/Projects/Cards/Cards Board.md"
expect "next: goal line wins" "$(section Cards "$(gather "" "$(at "2026-11-09 12:00")")")" "next: CRD-1 · Only card — Ship it (to do)"

# --- Board: a card outside Done whose PR is merged moves to the end of Done, ticked ---
cat > "$FIX/stub/gh.sh" <<'SH'
case "$*" in
  "pr view https://github.com/acme/acme/pull/7 --json state -q .state"|"pr view https://github.com/acme/acme/pull/9 --json state -q .state") echo MERGED ;;
  "pr view https://github.com/acme/acme/pull/8 --json state -q .state") echo OPEN ;;
  *) echo "unexpected: $*" >&2; exit 3 ;;
esac
SH
cards="$VAULT/Projects/Cards/Cards Board.md"
settings=$'%% kanban:settings\n```\n{}\n```\n%%'
cat > "$cards" <<MD
## To do

- [ ] **CRD-1 · Open PR**
	PR https://github.com/acme/acme/pull/8
- [ ] **CRD-2 · Merged from to do**
	PR https://github.com/acme/acme/pull/7

## In progress

- [ ] **CRD-3 · Merged**
	Text
	PR https://github.com/acme/acme/pull/9


## Done

**Complete**
- [x] **CRD-0 · Old**
	PR https://github.com/acme/acme/pull/1




$settings
MD
: > "$FIX/calls"
s=$(section Cards "$(gather "" "$(at "2026-11-09 12:00")")")
expect "board: merged card from to do moves" "$s" "moved: CRD-2 to Done (PR #7 merged)"
expect "board: merged card from in progress moves" "$s" "moved: CRD-3 to Done (PR #9 merged)"
expect "board: next reads the board after the move" "$s" "next: CRD-1 · Open PR (to do)"
grep -q 'pull/1 ' "$FIX/calls" && fail "board: cards in Done are not checked" || pass "board: cards in Done are not checked"
want=$(cat <<MD
## To do

- [ ] **CRD-1 · Open PR**
	PR https://github.com/acme/acme/pull/8

## In progress



## Done

**Complete**
- [x] **CRD-0 · Old**
	PR https://github.com/acme/acme/pull/1
- [x] **CRD-2 · Merged from to do**
	PR https://github.com/acme/acme/pull/7
- [x] **CRD-3 · Merged**
	Text
	PR https://github.com/acme/acme/pull/9




$settings
MD
)
[ "$(cat "$cards")" = "$want" ] && pass "board: blocks moved, ticked, rest untouched" ||
  { fail "board: blocks moved, ticked, rest untouched"; diff <(echo "$want") "$cards"; }
s=$(section Cards "$(GH_FAIL="HTTP 401: Bad credentials" gather "" "$(at "2026-11-09 12:00")")")
expect "board: gh fails → one line with the fix" "$s" "error: Board: HTTP 401: Bad credentials — gh auth login"
printf '## To do\n\n- [ ] **CRD-4 · Merged**\n\tPR https://github.com/acme/acme/pull/7\n' > "$cards"
s=$(section Cards "$(gather "" "$(at "2026-11-09 12:00")")")
expect "board: no Done column → reported, card stays" "$s" "error: Board: no Done column on $cards"
grep -q '^- \[ \] \*\*CRD-4' "$cards" && pass "board: no Done column → board untouched" || fail "board: no Done column → board untouched"
printf '## To do\n\n- [ ] **CRD-1 · Only card**\n\tLong text. More.\n\tZiel: Ship it\n' > "$cards"

# --- Folder lookup fails: one line with the reason and the fix; no folder at all stays silent (Quiet above) ---
fixture_note Twin "repo: https://git.acme.test/acme/twin.git"
fixture_repo "$PROJECTS_ROOT/twin-a" https://git.acme.test/acme/twin.git
fixture_repo "$PROJECTS_ROOT/twin-b" https://git.acme.test/acme/twin
fixture_note Moved "local: $FIX/gone"
out=$(gather "" "$(at "2026-11-09 12:00")")
expect "folder: two clones → reason and fix" "$(section Twin "$out")" \
  "error: folder: two clones of https://git.acme.test/acme/twin.git under the projects root: $PROJECTS_ROOT/twin-a $PROJECTS_ROOT/twin-b — set local: <folder> in the project note"
expect "folder: local missing → reason and fix" "$(section Moved "$out")" \
  "error: folder: $FIX/gone not found — set local: <folder> in the project note"

# --- Jira: key from commits, snapshot diff, Next from the open sprint ---
fixture_note Jet
J="$PROJECTS_ROOT/jet"
fixture_repo "$J"; commit "$J" "2026-11-05 10:00" "JET-11 Add login"; commit "$J" "2026-11-05 11:00" "JET-12 Fix crash"
fixture_note Utf; U="$PROJECTS_ROOT/utf"
fixture_repo "$U"; commit "$U" "2026-11-05 10:00" "Read UTF-8"; commit "$U" "2026-11-05 11:00" "More UTF-16"
# issue <key> <status> <category> <assignee email> <summary> [type] [priority id] [labels json]
issue() {
  jq -nc --arg k "$1" --arg s "$2" --arg c "$3" --arg a "$4" --arg t "$5" --arg ty "${6:-Task}" --arg p "${7:-3}" --argjson l "${8:-[]}" \
    '{key: $k, fields: {summary: $t, status: {name: $s, statusCategory: {key: $c}}, issuetype: {name: $ty},
      priority: {id: $p}, labels: $l, assignee: {emailAddress: $a, displayName: ($a | split("@")[0])}}}'
}
sprint() { jq -s . > "$FIX/sprint.json"; }
cat > "$FIX/stub/acli.sh" <<'SH'
case "$*" in
  "jira auth status") printf '✓ Authenticated\n  Site: acme.atlassian.test\n  Email: jq@acme.test\n' ;;
  *"project = JET AND sprint in openSprints()"*) cat "$FIX/sprint.json" ;;
  *"project = UTF"*) echo "✗ Error: failed to parse JQL query: the value 'utf' does not exist for the field 'project'."; exit 1 ;;
  *) exit 3 ;;
esac
SH
{ issue JET-11 "To Do" new jq@acme.test "Add login" Story
  issue JET-12 Review indeterminate max@acme.test "Fix crash"
  issue JET-14 "To Do" new jq@acme.test "Patch prod" Task 3 '["hotfix"]'
  issue JET-16 "To Do" new max@acme.test "Not mine" Bug 1; } | sprint
rm -rf "$BRIEFING_STATE"
out=$(gather)
s=$(section Jet "$out")
expect "jira first run: next is the /ticket pick (hotfix first)" "$s" "next: JET-14 Patch prod (top pick)"
grep -q '^jira' <<<"$s" && fail "jira first run: no diff" || pass "jira first run: no diff"
grep -qx '# Utf' <<<"$out" && fail "jira: key unknown to Jira → nothing" || pass "jira: key unknown to Jira → nothing"
{ issue JET-11 "To Do" new jq@acme.test "Add login" Story
  issue JET-12 "In Progress" indeterminate max@acme.test "Fix crash"
  issue JET-14 "In Progress" indeterminate jq@acme.test "Patch prod" Task 3 '["hotfix"]'
  issue JET-15 "To Do" new max@acme.test "New thing"
  issue JET-16 "To Do" new max@acme.test "Not mine" Bug 1; } | sprint
s=$(section Jet "$(gather "" "$(at "2026-11-09 13:00")")")
expect "jira: added" "$s" "jira added: JET-15 [To Do] max — New thing"
expect "jira: back" "$s" "jira back: JET-12 Review → In Progress max — Fix crash"
expect "jira: next in progress" "$s" "next: JET-14 Patch prod (in progress)"
[ "$(grep -c '^jira' <<<"$s")" -eq 2 ] && pass "jira: only changes" || fail "jira: only changes: $s"
s=$(section Jet "$(ACLI_FAIL="✗ Error: unauthorized" gather "" "$(at "2026-11-09 14:00")")")
expect "jira fails: one line with the fix" "$s" "error: Jira: ✗ Error: unauthorized — acli jira auth login"
[ "$(ACLI_FAIL="✗ Error: unauthorized" gather "" "$(at "2026-11-09 14:00")" | grep -c '^error: Jira')" -eq 1 ] &&
  pass "jira fails: once per run, not per project (Utf too)" || fail "jira fails: once per run, not per project (Utf too)"
s=$(section Jet "$(gather "" "$(at "2026-11-09 15:00")")")
grep -q '^jira' <<<"$s" && fail "jira fails: snapshot kept" || pass "jira fails: snapshot kept"

# --- Sentry: projects from committed DSNs, staging if present, new/regressed since the last run ---
fixture_note Shop
S="$PROJECTS_ROOT/shop"
fixture_repo "$S"
echo "dsn = 'https://k@o1.ingest.us.sentry.io/4501'; api = 'https://k@o1.ingest.us.sentry.io/4502'" > "$S/sentry.ts"
git -C "$S" add -A; commit "$S" "2026-11-05 09:00" "Add Sentry"
cat > "$FIX/stub/sentry.sh" <<'SH'
case "$*" in
  "api organizations/") echo '[{"slug":"acme"}]' ;;
  "api organizations/acme/projects/") echo '[{"id":"4501","slug":"shop"},{"id":"4502","slug":"api"}]' ;;
  "api projects/acme/shop/environments/") echo '[{"name":"production"},{"name":"staging"}]' ;;
  "api projects/acme/api/environments/") echo '[{"name":"production"}]' ;;
  "issue list acme/shop --query is:unresolved level:error environment:staging "*) echo '{"data":[
    {"shortId":"SHOP-1","firstSeen":"2026-11-08T10:00:00.123456Z","lastSeen":"2026-11-08T10:00:00Z","substatus":"new"},
    {"shortId":"SHOP-2","firstSeen":"2026-10-01T10:00:00Z","lastSeen":"2026-11-07T10:00:00Z","substatus":"regressed"},
    {"shortId":"SHOP-3","firstSeen":"2026-10-01T10:00:00Z","lastSeen":"2026-11-08T10:00:00Z","substatus":"ongoing"}]}' ;;
  "issue list acme/api --query is:unresolved level:error "*) echo '[
    {"shortId":"API-1","firstSeen":"2026-11-07T00:00:00.5+00:00","lastSeen":"2026-11-07T00:00:00Z","substatus":"new"}]' ;;
  *) echo "unexpected: $*" >&2; exit 3 ;;
esac
SH
rm -rf "$BRIEFING_STATE"
s=$(section Shop "$(gather)")
expect "sentry: staging, new and regressed" "$s" "sentry acme/shop staging: 3 issues, new: SHOP-1, regressed: SHOP-2"
expect "sentry: no staging → no filter" "$s" "sentry acme/api: 1 issues, new: API-1"
grep -q '^sentry' <<<"$(section Shop "$(gather "" "$(at "2026-11-09 13:00")")")" && fail "sentry: nothing new since last run → no line" || pass "sentry: nothing new since last run → no line"
s=$(section Shop "$(SENTRY_FAIL="Error: not authenticated" gather "" "$(at "2026-11-09 14:00")")")
expect "sentry fails: one line with the fix" "$s" "error: Sentry: sentry api organizations/ failed: Error: not authenticated — sentry auth login"
grep -q 'Sentry' <<<"$(section Acme "$(SENTRY_FAIL=x gather "" "$(at "2026-11-09 14:00")")")" && fail "sentry: no DSN → nothing" || pass "sentry: no DSN → nothing"
# A DSN outside Quinn's Sentry organizations (a test fixture, a vendor's DSN) → nothing, no error
fixture_note Fixtures
F="$PROJECTS_ROOT/fixtures"
fixture_repo "$F"
echo "dsn = 'https://k@o5.ingest.sentry.io/999'; ok = 'https://k@o1.ingest.us.sentry.io/4502'" > "$F/t.sh"
git -C "$F" add -A; commit "$F" "2026-11-05 09:00" "Add fixture"
s=$(section Fixtures "$(gather "" "$(at "2026-11-09 15:00")")")
grep -q 'error: Sentry' <<<"$s" && fail "sentry: foreign DSN → no error: $s" || pass "sentry: foreign DSN → no error"
echo "dsn = 'https://k@o5.ingest.sentry.io/999'" > "$F/t.sh"
git -C "$F" add -A; commit "$F" "2026-11-05 09:01" "Only foreign"
s=$(section Fixtures "$(gather "" "$(at "2026-11-09 16:00")")")
grep -q 'Sentry' <<<"$s" && fail "sentry: only foreign DSNs → nothing: $s" || pass "sentry: only foreign DSNs → nothing"

# --- Dependabot: GitHub repos only, new PRs since the last run ---
git -C "$S" remote add origin git@github.com:acme/shop.git
git -C "$A" remote add origin https://git.acme.test/acme/acme.git
cat > "$FIX/stub/gh.sh" <<'SH'
case "$*" in
  "pr list -R acme/shop --author app/dependabot --state open "*) echo '[
    {"number":12,"title":"Bump left-pad from 1.0 to 1.1","createdAt":"2026-11-08T03:00:00Z"},
    {"number":9,"title":"Bump old","createdAt":"2026-10-01T03:00:00Z"}]' ;;
  *) echo "unexpected: $*" >&2; exit 3 ;;
esac
SH
rm -rf "$BRIEFING_STATE"
out=$(gather)
expect "dependabot: new PRs" "$(section Shop "$out")" "dependabot: 1 new of 2 open: #12 Bump left-pad from 1.0 to 1.1"
grep -qi dependabot <<<"$(section Acme "$out")" && fail "dependabot: non-GitHub origin → nothing" || pass "dependabot: non-GitHub origin → nothing"
grep -q '^dependabot' <<<"$(section Shop "$(gather "" "$(at "2026-11-09 13:00")")")" && fail "dependabot: nothing new → no line" || pass "dependabot: nothing new → no line"
s=$(section Shop "$(GH_FAIL="HTTP 401: Bad credentials" gather "" "$(at "2026-11-09 14:00")")")
expect "dependabot fails: one line with the fix" "$s" "error: Dependabot: HTTP 401: Bad credentials — gh auth login"

# --- CLIs not installed: one line each with the fix ---
mkdir -p "$FIX/tools"; ln -s "$(command -v jq)" "$(command -v git)" "$FIX/tools/"
out=$(PATH="$FIX/tools:/usr/bin:/bin" gather "" "$(at "2026-11-09 15:00")")
expect "absent acli" "$(section Jet "$out")" "error: Jira: acli not installed — install the Atlassian CLI (acli)"
[ "$(grep -c '^error: Jira' <<<"$out")" -eq 1 ] && pass "absent acli: once per run" || fail "absent acli: once per run"
expect "absent sentry" "$(section Shop "$out")" "error: Sentry: sentry not installed — install the Sentry CLI (sentry)"
expect "absent gh" "$(section Shop "$out")" "error: Dependabot: gh not installed — install the GitHub CLI (gh)"

done_testing
