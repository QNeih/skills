#!/usr/bin/env bash
# Sentry projects of a repo (skills/sentry-fix/sentry-projects.sh): DSN derivation and the note override.
# `sentry` is a stub on PATH; no live service is called.
. "$(dirname "$0")/lib.sh"
SCRIPT="$REPO_DIR/skills/sentry-fix/sentry-projects.sh"
fixture_new
mkdir -p "$FIX/bin"
cat > "$FIX/bin/sentry" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FIX/sentry-calls"
[ -n "${SENTRY_FAIL:-}" ] && { echo "Error: not authenticated" >&2; exit 1; }
[ "$*" = "api projects/" ] || exit 2
echo '[{"id":"4501","slug":"web","organization":{"slug":"acme"}},
       {"id":"4502","slug":"api","organization":{"slug":"acme"}},
       {"id":"77","slug":"other","organization":{"slug":"globex"}}]'
SH
chmod +x "$FIX/bin/sentry"
export PATH="$FIX/bin:$PATH" FIX
run() { "$SCRIPT" "$@" 2>&1; }
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@acme.test commit -qm files; }

# Two DSNs in committed files (regions us and de, one repeated); an untracked file's DSN is ignored
r="$PROJECTS_ROOT/acme"
fixture_repo "$r"
mkdir -p "$r/client/src" "$r/server"
echo "export const dsn = 'https://abc123@o11.ingest.us.sentry.io/4501';" > "$r/client/src/env.ts"
echo "dsn: 'https://abc123@o11.ingest.us.sentry.io/4501'," > "$r/client/src/env.prod.ts"
echo '{ "Sentry": { "Dsn": "https://def456@o11.ingest.de.sentry.io/4502" } }' > "$r/server/appsettings.json"
commit_all "$r"
echo 'SENTRY_DSN=https://zzz@o99.ingest.sentry.io/77' > "$r/.env"
out=$(run "$r")
expect "dsn: client project" "$out" "sentry: acme/web"
expect "dsn: server project" "$out" "sentry: acme/api"
[ "$(grep -c '^sentry:' <<<"$out")" -eq 2 ] && pass "dsn: one line per project, untracked ignored" || fail "dsn: one line per project: $out"

# Works from any folder: dir is an argument
out=$(cd /tmp && run "$r")
expect "dsn: from another folder" "$out" "sentry: acme/web"

# Override in the note wins; sentry is not called
fixture_note Acme "sentry: acme/web"
rm -f "$FIX/sentry-calls"
out=$(run "$r" "$VAULT/Projects/Acme/Acme.md")
expect "override: project" "$out" "sentry: acme/web"
[ "$(grep -c '^sentry:' <<<"$out")" -eq 1 ] && pass "override: narrows to one" || fail "override: narrows to one: $out"
[ ! -f "$FIX/sentry-calls" ] && pass "override: no sentry call" || fail "override: no sentry call"

fixture_note Multi "sentry: \"acme/web, globex/other\""
out=$(run "$r" "$VAULT/Projects/Multi/Multi.md")
expect "override list: first" "$out" "sentry: acme/web"
expect "override list: second" "$out" "sentry: globex/other"

# Note without the override → derived
fixture_note Plain "repo: https://git.acme.test/acme"
expect "note without override derives" "$(run "$r" "$VAULT/Projects/Plain/Plain.md")" "sentry: acme/api"

# No DSN committed
fixture_repo "$PROJECTS_ROOT/bare"
out=$(run "$PROJECTS_ROOT/bare"); rc=$?
expect "no dsn: none" "$out" "sentry: none"
expect "no dsn: reason" "$out" "reason: no Sentry DSN committed in $PROJECTS_ROOT/bare; set sentry: <org>/<project> in the project note"
[ $rc -eq 0 ] && pass "failure exits 0" || fail "failure exits 0 (got $rc)"

# Not a git repo
mkdir -p "$FIX/plain"
expect "no git: reason" "$(run "$FIX/plain")" "reason: $FIX/plain is not a git repo"

# sentry api fails → its error in the reason
out=$(SENTRY_FAIL=1 run "$r")
expect "api fails: none" "$out" "sentry: none"
expect "api fails: reason" "$out" "reason: sentry api projects/ failed: Error: not authenticated"

# DSN id not visible to the logged-in account
r2="$PROJECTS_ROOT/stranger"
fixture_repo "$r2"
echo "https://k@o5.ingest.sentry.io/123456" > "$r2/sentry.conf"
commit_all "$r2"
out=$(run "$r2")
expect "unknown id: none" "$out" "sentry: none"
expect "unknown id: reason" "$out" "reason: Sentry project id 123456 (from a DSN) not found by sentry api projects/"

# One DSN known, one not → the known project, plus a skipped line
echo "https://k@o11.ingest.us.sentry.io/4501" >> "$r2/sentry.conf"
commit_all "$r2"
out=$(run "$r2")
expect "partial: known project" "$out" "sentry: acme/web"
expect "partial: skipped line" "$out" "skipped: Sentry project id 123456 (from a DSN) not found by sentry api projects/"
grep -q '^sentry: none' <<<"$out" && fail "partial: no none line" || pass "partial: no none line"

done_testing
