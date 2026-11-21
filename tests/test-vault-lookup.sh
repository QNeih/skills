#!/usr/bin/env bash
# Project note lookup of /wiki (skills/wiki/vault-lookup.sh) against a fixture vault.
. "$(dirname "$0")/lib.sh"
LOOKUP="$REPO_DIR/skills/wiki/vault-lookup.sh"
fixture_new
fixture_note "Tür an Tür"
fixture_note Acme
echo "board" > "$VAULT/wiki/projects/Acme Board.md"
look() { bash "$LOOKUP" "$@" 2>&1; }

out=$(look --note Acme)
expect "exact name: project" "$out" "project: Acme"
expect "exact name: note path" "$out" "note: $VAULT/wiki/projects/Acme.md"
expect "case, spaces and hyphens ignored" "$(look --note "tür-an-tür")" "project: Tür an Tür"
nfd=$(perl -CSA -MUnicode::Normalize -le 'print NFD(shift)' "Tür an Tür")
expect "decomposed umlaut matches" "$(look --note "$nfd")" "project: Tür an Tür"
expect "board file is not a note" "$(look --note "Acme Board")" "project: none"
out=$(look --note Shop)
expect "unknown: project none" "$out" "project: none"
expect "unknown: reason" "$out" "reason: no project note named Shop"
expect "no name: usage" "$(look --note)" "reason: usage: vault-lookup.sh --note NAME"
expect "no vault: reason" "$(VAULT= look --note Acme)" "reason: VAULT must be set"
look --note Shop >/dev/null; expect "exits 0 on none" "$?" "0"

done_testing
