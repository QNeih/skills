#!/usr/bin/env bash
# send/decision-note.sh: writes one decision note to the brain's raw/<Name>/ from the ticket's
# Decisions lines and the ADRs and glossary entries the branch added or changed.
. "$(dirname "$0")/lib.sh"
fixture_new
note="$REPO_DIR/skills/send/decision-note.sh"
today=$(date +%F)
mkdir -p "$VAULT/wiki/projects"
printf -- '---\ntags: [project]\n---\n' > "$VAULT/wiki/projects/Acme Shop.md"

# ticket <file> <decisions section body>
ticket() {
  printf '# ACM-7: Pay by invoice / later\n\nref: QuinnNei/acme-shop#7\nbase: main\n\n## Summary\n\nPay later.\n\n## Decisions\n\n%s\n\n## Acceptance criteria\n\n- works\n' "$2" > "$1"
}
run() { out=$(cd "$repo" && VAULT=$VAULT bash "$note" "$@"); rc=$?; }
commit() { git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@acme.test commit -q -m "$1"; }

# --- a git project whose base already has a glossary and an ADR ---
remote="$FIX/acme.git" repo="$PROJECTS_ROOT/acme-shop"
git init -q --bare -b main "$remote"
fixture_repo "$repo" "$remote"
mkdir -p "$repo/docs/adr"
printf '# Acme\n\n## Language\n\n**Order**:\nA purchase.\n_Avoid_: buy\n\n**Invoice**:\nA bill.\n_Avoid_: bill\n\n**Refund**:\nMoney back.\n' > "$repo/GLOSSARY.md"
echo '# Old decision' > "$repo/docs/adr/0001-old.md"
commit base
git -C "$repo" push -q origin main
git -C "$repo" switch -q -c feature/ACM-7
# The branch changes one entry, adds one, deletes one, adds an ADR and leaves the old ADR alone
printf '# Acme\n\n## Language\n\n**Order**:\nA purchase.\n_Avoid_: buy\n\n**Invoice**:\nA request for payment.\n_Avoid_: bill\n\n**Due date**:\nThe day an invoice must be paid.\n' > "$repo/GLOSSARY.md"
printf '# Pay later by invoice\n\nWe keep invoices in the shop, not in the ERP.\n' > "$repo/docs/adr/0002-pay-later.md"
commit work
t="$FIX/ticket.md"
ticket "$t" '- Invoice in the shop. Why: the ERP is slow. Rejected: ERP invoices, they arrive a day late.'

run --ticket "$t" --project acme-shop --base main
file="$VAULT/raw/Acme Shop/$today ACM-7 Pay by invoice later.md"
expect "prints the note's path" "$out" "note: $file"
[ $rc -eq 0 ] && [ -f "$file" ] && pass "writes the note into raw/<page name>/, created when missing" || { fail "note written"; echo "$out"; ls -R "$VAULT/raw"; }
body=$(cat "$file" 2>/dev/null)
expect "title line" "$body" "# ACM-7: Pay by invoice / later"
expect "decision line verbatim" "$body" "- Invoice in the shop. Why: the ERP is slow. Rejected: ERP invoices, they arrive a day late."
expect "added ADR in full" "$body" "We keep invoices in the shop, not in the ERP."
expect "changed glossary entry in full: term" "$body" "**Invoice**:"
expect "changed glossary entry in full: unchanged line" "$body" "_Avoid_: bill"
expect "added glossary entry" "$body" "The day an invoice must be paid."
grep -qF 'Old decision' <<<"$body" && fail "an unchanged ADR stays out" || pass "an unchanged ADR stays out"
grep -qF 'Order' <<<"$body" && fail "an unchanged entry stays out" || pass "an unchanged entry stays out"
grep -qF 'Refund' <<<"$body" && fail "a deleted entry stays out" || pass "a deleted entry stays out"

# A rerun on a later day overwrites the ticket's earlier note, but not another ticket's
older="$VAULT/raw/Acme Shop/2026-01-02 ACM-7 Pay by invoice later.md"
mv "$file" "$older"
echo other > "$VAULT/raw/Acme Shop/2026-01-02 ACM-70 Other.md"
run --ticket "$t" --project acme-shop --base main
expect "rerun: prints the earlier note's path" "$out" "note: $older"
[ "$(ls "$VAULT/raw/Acme Shop" | wc -l | tr -d ' ')" -eq 2 ] && grep -qF 'We keep invoices' "$older" &&
  pass "rerun: the earlier note is overwritten, no second note" || { fail "rerun: one note per ticket"; ls "$VAULT/raw/Acme Shop"; }

# A close: the branch has nothing on it; the reason is a decision line
git -C "$repo" switch -q main
rm -rf "$VAULT/raw"
run --ticket "$t" --project acme-shop --base main --close "Duplicate of ACM-3"
body=$(cat "$file" 2>/dev/null)
expect "close: the reason is a decision line with both labels" "$body" "- Closed without code. Why: Duplicate of ACM-3. Rejected: none."
run --ticket "$t" --project acme-shop --base main --close "Duplicate of ACM-3."
expect "close: a reason ending in a period keeps one period" "$(cat "$file" 2>/dev/null)" "- Closed without code. Why: Duplicate of ACM-3. Rejected: none."
expect "close: the ticket's decisions stay" "$body" "- Invoice in the shop. Why: the ERP is slow. Rejected: ERP invoices, they arrive a day late."
grep -qF 'ADR' <<<"$body" && fail "close: no ADR section" || pass "close: no ADR section"

# Nothing to write: no decisions, no ADR or glossary change, no close
rm -rf "$VAULT/raw"
ticket "$t" 'none'
run --ticket "$t" --project acme-shop --base main
expect "nothing to write: no note" "$out" "note: none"
[ $rc -eq 0 ] && [ ! -e "$VAULT/raw" ] && pass "nothing to write: no file, exit 0" || fail "nothing to write: no file, exit 0 (rc $rc)"

# The template placeholder counts as no decisions
ticket "$t" '<one line per decision: `- <what>. Why: <reason>. Rejected: <option and its reason, or none>.`; "none" when the work held no choice>'
run --ticket "$t" --project acme-shop --base main
expect "placeholder: no note" "$out" "note: none"

# No git: only the decisions
ticket "$t" '- Keep paper invoices. Why: the tax office asks for them. Rejected: none.'
repo="$FIX/nogit"; mkdir -p "$repo"
run --ticket "$t" --project "ACME shop"
grep -qF -- '- Keep paper invoices. Why: the tax office asks for them. Rejected: none.' "$file" 2>/dev/null && pass "no git: decisions only, Rejected: none accepted, page matched ignoring case and spaces" || { fail "no git: decisions only"; echo "$out"; }

# A decision line without a label is refused: the error names the first such line, no note
rm -rf "$VAULT/raw"
ticket "$t" "$(printf '%s\n' '- Keep paper invoices. Why: the tax office asks for them. Rejected: none.' '- Send them by post. Rejected: e-mail.' '- Print in colour, because of the logo.')"
run --ticket "$t" --project acme-shop
expect "line without Why: the error names the label and the line" "$out" "error: decision line without Why: in $t: - Send them by post. Rejected: e-mail."
[ $rc -eq 1 ] && [ ! -e "$VAULT/raw" ] && pass "line without Why: exit 1, no note" || fail "line without Why: exit 1, no note (rc $rc)"
grep -qF 'Print in colour' <<<"$out" && fail "only the first refused line is named" || pass "only the first refused line is named"
ticket "$t" '- Send them by post. Why: customers ask for paper.'
run --ticket "$t" --project acme-shop
expect "line without Rejected: the error names the label" "$out" "error: decision line without Rejected: in $t: - Send them by post. Why: customers ask for paper."
ticket "$t" '- Print in colour, because of the logo.'
run --ticket "$t" --project acme-shop --close "Duplicate of ACM-3"
expect "line without both labels: the error names both, on a close too" "$out" "error: decision line without Why: and Rejected: in $t: - Print in colour, because of the logo."
[ $rc -eq 1 ] && [ ! -e "$VAULT/raw" ] && pass "line without both labels: exit 1, no note" || fail "line without both labels: exit 1, no note (rc $rc)"
ticket "$t" '- Keep paper invoices. Why: the tax office asks for them. Rejected: none.'

# No project page: an error, no file
rm -rf "$VAULT/raw"
run --ticket "$t" --project billing
grep -q '^error: no project page' <<<"$out" && [ $rc -eq 1 ] && [ ! -e "$VAULT/raw" ] && pass "no project page: error, exit 1, no file" || { fail "no project page"; echo "$out"; }

# No vault
out=$(cd "$repo" && VAULT= bash "$note" --ticket "$t" --project acme-shop); rc=$?
grep -q '^error: ' <<<"$out" && [ $rc -eq 1 ] && pass "no vault: error, exit 1" || { fail "no vault"; echo "$out"; }

# A title line without `<id>: `
printf '# Pay later\n\n## Decisions\n\n- a. Why: b. Rejected: none.\n' > "$t"
out=$(cd "$repo" && VAULT=$VAULT bash "$note" --ticket "$t" --project acme-shop); rc=$?
grep -q "^error: the first line of .* is not '# <id>: <title>'" <<<"$out" && [ $rc -eq 1 ] && [ ! -e "$VAULT/raw" ] &&
  pass "title line without id: error, exit 1, no file" || { fail "title line without id"; echo "$out"; }

# An option without its value
out=$(cd "$repo" && VAULT=$VAULT bash "$note" --project acme-shop --ticket 2>&1); rc=$?
expect "option without value: error line" "$out" "error: --ticket needs a value"
[ $rc -eq 1 ] && pass "option without value: exit 1" || fail "option without value: exit 1 (rc $rc)"

done_testing
