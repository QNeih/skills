#!/usr/bin/env bash
# Project lookup (skills/work/project.sh): derivation cases from the spec.
. "$(dirname "$0")/lib.sh"
LOOKUP="$REPO_DIR/skills/work/project.sh"
fixture_new
lookup() { (cd "$1" && "$LOOKUP" "${@:2}" 2>&1); }

# Folder name ↔ note name, case differs
fixture_note Acme
fixture_repo "$PROJECTS_ROOT/acme"
out=$(lookup "$PROJECTS_ROOT/acme")
expect "case: project" "$out" "project: Acme"
expect "case: note" "$out" "note: $VAULT/Projects/Acme/Acme.md"
expect "case: dir" "$out" "dir: $PROJECTS_ROOT/acme"

# Space in the note name vs hyphen in the folder name
fixture_note "Acme Proto"
fixture_repo "$PROJECTS_ROOT/Acme-Proto"
expect "space vs hyphen" "$(lookup "$PROJECTS_ROOT/Acme-Proto")" "project: Acme Proto"

# Note name stored in NFD, folder name in NFC
nfd=$(perl -CSA -MUnicode::Normalize -e 'print NFD("Gr\x{fc}n Acme")')
nfc=$(perl -CSA -MUnicode::Normalize -e 'print NFC("Gr\x{fc}n-Acme")')
fixture_note "$nfd"
mkdir -p "$PROJECTS_ROOT/$nfc"
out=$(lookup "$PROJECTS_ROOT/$nfc")
expect "NFD note, NFC folder (no git)" "$out" "dir: $PROJECTS_ROOT/$nfc"
grep -q '^project: Gr' <<<"$out" && pass "NFD note found" || fail "NFD note found: $out"

# Worktree and subfolder resolve to the main checkout
git -C "$PROJECTS_ROOT/acme" worktree add -q "$FIX/wt-acme" 2>/dev/null
mkdir -p "$FIX/wt-acme/src/deep"
out=$(lookup "$FIX/wt-acme/src/deep")
expect "worktree: dir" "$out" "dir: $PROJECTS_ROOT/acme"
expect "worktree: project" "$out" "project: Acme"

# Note whose repo equals origin, ignoring .git and case; folder named differently
fixture_note Widget "repo: https://git.acme.test/Org/WIDGET"
fixture_repo "$PROJECTS_ROOT/w2" https://git.acme.test/org/widget.git
expect "repo match" "$(lookup "$PROJECTS_ROOT/w2")" "project: Widget"

# local override: note whose local equals the folder or is a parent of it; wins over name and repo
fixture_note Gadget "local: \"$FIX/elsewhere/gadget\""
mkdir -p "$FIX/elsewhere/gadget/sub" "$FIX/elsewhere/gadget-two"
out=$(lookup "$FIX/elsewhere/gadget/sub")
expect "local parent: project" "$out" "project: Gadget"
expect "local parent, no git: dir is the local folder" "$out" "dir: $FIX/elsewhere/gadget"
out=$(lookup "$FIX/elsewhere/gadget")
expect "local equal" "$out" "project: Gadget"
expect "local is not a prefix match" "$(lookup "$FIX/elsewhere/gadget-two")" "project: none"
fixture_note Over "local: $PROJECTS_ROOT/w2"
expect "local beats repo" "$(lookup "$PROJECTS_ROOT/w2")" "project: Over"

# Failure reasons: a reason line, exit 0
fixture_repo "$FIX/outside/acme"
out=$(lookup "$FIX/outside/acme"); rc=$?
expect "outside root: no project" "$out" "project: none"
expect "outside root: reason" "$out" "reason: $FIX/outside/acme is outside the projects root $PROJECTS_ROOT"
[ $rc -eq 0 ] && pass "failure exits 0" || fail "failure exits 0 (got $rc)"

fixture_repo "$PROJECTS_ROOT/widget-copy" https://git.acme.test/org/widget
expect "two clones: reason" "$(lookup "$PROJECTS_ROOT/widget-copy")" \
  "reason: two clones of https://git.acme.test/Org/WIDGET under the projects root: $PROJECTS_ROOT/w2 $PROJECTS_ROOT/widget-copy"

mkdir -p "$PROJECTS_ROOT/misc"
expect "no git, other name: reason" "$(lookup "$PROJECTS_ROOT/misc")" "reason: no project note named like misc"

fixture_repo "$PROJECTS_ROOT/stray" https://git.acme.test/org/stray.git
expect "git, no match: reason" "$(lookup "$PROJECTS_ROOT/stray")" \
  "reason: no project note with repo https://git.acme.test/org/stray.git or named like stray"

expect "no VAULT: reason" "$(cd "$PROJECTS_ROOT/acme" && VAULT= "$LOOKUP")" "reason: VAULT and PROJECTS_ROOT must be set"

# Board: vault board file → vault, key from the card prefix
cat > "$VAULT/Projects/Acme/Acme Board.md" <<'MD'
## To do

- [ ] **ACM-38 · Fix the thing** #bug
- [ ] **ACM-39 · Another thing**
	Mentions OTHER-1 in the text
MD
out=$(lookup "$PROJECTS_ROOT/acme")
expect "vault board" "$out" "board: vault"
expect "vault board file" "$out" "board-file: $VAULT/Projects/Acme/Acme Board.md"
expect "vault key from cards" "$out" "key: ACM"

# Board: override from the note
fixture_note Gizmo "board: https://boards.acme.test/org/gizmo"
fixture_repo "$PROJECTS_ROOT/gizmo"
out=$(lookup "$PROJECTS_ROOT/gizmo")
expect "board override" "$out" "board: https://boards.acme.test/org/gizmo"
grep -q '^key:' <<<"$out" && fail "board override: no key line" || pass "board override: no key line"

# Board: Jira candidate from branches and commit subjects; UTF-8 / SHA-256 repeated do not win
fixture_note Jet
fixture_repo "$PROJECTS_ROOT/jet"
c() { git -C "$PROJECTS_ROOT/jet" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m "$1"; }
for i in 1 2 3 4 5; do c "Read files as UTF-8"; c "Check SHA-256 sums"; done
c "JET-11 Add login"; c "Fix JET-12 crash"
git -C "$PROJECTS_ROOT/jet" branch feature/JET-13
out=$(lookup "$PROJECTS_ROOT/jet")
expect "jira candidate" "$out" "board: jira-candidate"
expect "jira key from commits, not UTF/SHA" "$out" "key: JET"

# Board: nothing found
out=$(lookup "$PROJECTS_ROOT/Acme-Proto")
expect "no board" "$out" "board: none"

# Reverse lookup: note → folder one level under the projects root
rev() { "$LOOKUP" --note "$1" 2>&1; }
out=$(rev Acme)
expect "reverse by name: dir" "$out" "dir: $PROJECTS_ROOT/acme"
expect "reverse by name: note" "$out" "note: $VAULT/Projects/Acme/Acme.md"
expect "reverse: board lines too" "$out" "board-file: $VAULT/Projects/Acme/Acme Board.md"
expect "reverse: jira candidate from the folder" "$(rev Jet)" "board: jira-candidate"
expect "reverse: board override" "$(rev Gizmo)" "board: https://boards.acme.test/org/gizmo"
expect "reverse NFD note by NFC name" "$(rev "$nfc")" "dir: $PROJECTS_ROOT/$nfc"
expect "reverse local" "$(rev Gadget)" "dir: $FIX/elsewhere/gadget"
fixture_note Sprocket "repo: https://git.acme.test/org/sprocket"
fixture_repo "$PROJECTS_ROOT/sp" https://git.acme.test/org/sprocket.git
expect "reverse repo" "$(rev Sprocket)" "dir: $PROJECTS_ROOT/sp"
expect "reverse two clones" "$(rev Widget)" \
  "reason: two clones of https://git.acme.test/Org/WIDGET under the projects root: $PROJECTS_ROOT/w2 $PROJECTS_ROOT/widget-copy"
fixture_note Lonely
expect "reverse no folder" "$(rev Lonely)" "reason: no folder under the projects root named like Lonely"
expect "reverse no note" "$(rev Nope)" "reason: no project note named Nope"

done_testing
