#!/usr/bin/env bash
# /briefing contacts (skills/briefing/gather.sh --contacts / --add-contact) against a fixture vault.
. "$(dirname "$0")/lib.sh"
GATHER="$REPO_DIR/skills/briefing/gather.sh"
fixture_new
export BRIEFING_STATE="$FIX/state" BRIEFING_TRANSCRIPTS="$FIX/transcripts"

# --- --contacts: every active project with its contacts (block or inline list) and client ---
fixture_note Acme "client: Acme Corp" "contacts:" "  - anna@acme.test" '  - "@acme.test"' "status: active"
fixture_note Beta 'contacts: ["@beta.test", Beta dev chat]'
fixture_note Quiet
fixture_note Old "status: done" "contacts: [old@old.test]"
out=$("$GATHER" --contacts 2>&1)
want='# Acme
client: Acme Corp
contact: anna@acme.test
contact: @acme.test
# Beta
contact: @beta.test
contact: Beta dev chat
# Quiet'
[ "$out" = "$want" ] && pass "contacts: active projects, both list forms, client" ||
  { fail "contacts: active projects, both list forms, client"; printf '     got:\n%s\n' "$out"; }

# --- --add-contact: entries into the note's frontmatter, quoted, no duplicates, other properties kept ---
c() { "$GATHER" --contacts | awk -v h="# $1" '$0 == h { on = 1; next } /^# / { on = 0 } on'; }
out=$("$GATHER" --add-contact Acme tom@acme.test ANNA@acme.test 2>&1)
expect "add: prints what was added" "$out" "contacts Acme: added tom@acme.test"
expect "add: new entry read back" "$(c Acme)" "contact: tom@acme.test"
[ "$(c Acme | grep -c '^contact:')" = 3 ] && pass "add: existing entry (any case) not added twice" || fail "add: existing entry (any case) not added twice"
expect "add: other properties kept" "$(cat "$VAULT/Projects/Acme/Acme.md")" "status: active"
expect "add: client kept" "$(c Acme)" "client: Acme Corp"
"$GATHER" --add-contact Quiet "@quiet.test" 'Quiet "ops" chat' >/dev/null
expect "add: no contacts yet → list created" "$(c Quiet)" "contact: @quiet.test"
expect "add: quotes survive" "$(c Quiet)" 'contact: Quiet "ops" chat'
expect "add: @ entries quoted (YAML)" "$(cat "$VAULT/Projects/Quiet/Quiet.md")" '  - "@quiet.test"'
expect "add: still a project" "$("$GATHER" --contacts)" "# Quiet"
"$GATHER" --add-contact Beta new@beta.test >/dev/null
expect "add: inline list kept with new entry" "$(c Beta)" "contact: Beta dev chat"
expect "add: inline list gets the entry" "$(c Beta)" "contact: new@beta.test"
expect "add: nothing new" "$("$GATHER" --add-contact Beta new@beta.test)" "contacts Beta: nothing new"
expect "add: unknown project" "$("$GATHER" --add-contact Nope a@b.test)" "error: no active project Nope"

done_testing
