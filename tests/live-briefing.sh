#!/usr/bin/env bash
# /briefing through claude -p: gather.sh runs against a fixture vault, repos and transcripts with
# sentry, gh and acli stubbed; step 2 (Microsoft 365) is replaced by fixed lines. Checks the brief
# keeps every line it was given, in the template's order, with the right Reply offers.
. "$(dirname "$0")/lib.sh"
fixture_new
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Bash(VAULT=*),Bash(date *),Bash(git *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}
export TZ=Europe/Berlin

# --- stubs: sentry, gh, acli answer from canned output; nothing reaches a live service ---
mkdir -p "$FIX/bin" "$FIX/transcripts"
printf '[user]\n\temail = q@acme.test\n\tname = Q\n' > "$FIX/gitconfig"
cat > "$FIX/bin/sentry" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "api organizations/") echo '[{"slug":"acme"}]' ;;
  "api organizations/acme/projects/") echo '[{"id":"4501","slug":"shop"}]' ;;
  "api projects/acme/shop/environments/") echo '[{"name":"production"}]' ;;
  "issue list acme/shop --query is:unresolved level:error "*) echo '[
    {"shortId":"SHOP-1","firstSeen":"2026-11-08T10:00:00Z","lastSeen":"2026-11-08T10:00:00Z","substatus":"new"},
    {"shortId":"SHOP-2","firstSeen":"2026-10-01T10:00:00Z","lastSeen":"2026-11-07T10:00:00Z","substatus":"regressed"}]' ;;
  *) exit 3 ;;
esac
SH
cat > "$FIX/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "pr list -R acme/shop --author app/dependabot --state open "*) echo '[
    {"number":12,"title":"Bump left-pad from 1.0 to 1.1","createdAt":"2026-11-08T03:00:00Z"}]' ;;
  *) exit 3 ;;
esac
SH
printf '#!/usr/bin/env bash\necho "✗ Error: unauthorized" >&2; exit 1\n' > "$FIX/bin/acli"
chmod +x "$FIX/bin/"*

# --- vault and projects: Shop has Did, Next, Sentry, Dependabot, a note; Jet only a Jira error; Quiet nothing ---
fixture_note Shop; fixture_note Jet; fixture_note Quiet
printf -- '- [ ] 2026-11-05 call the tax office\n- [ ] 2026-11-06 send the offer [[Shop]]\n' > "$VAULT/Briefing notes.md"
printf -- '## To do\n\n- [ ] **SHP-6 · Later card**\n\n## In progress\n\n- [ ] **SHP-5 · Checkout total wrong**\n' > "$VAULT/Projects/Shop/Shop Board.md"
shop="$PROJECTS_ROOT/shop" jet="$PROJECTS_ROOT/jet"
fixture_repo "$shop" git@github.com:acme/shop.git
echo "dsn = 'https://k@o1.ingest.us.sentry.io/4501'" > "$shop/sentry.ts"
git -C "$shop" add -A
GIT_AUTHOR_DATE="2026-11-06 15:00" GIT_COMMITTER_DATE="2026-11-06 15:00" git -C "$shop" -c user.email=q@acme.test -c user.name=Q commit -qm "Fix checkout rounding"
git -C "$shop" checkout -q -b bugfix/SHP-5
d="$FIX/transcripts/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$shop")"; mkdir -p "$d"
jq -nc '{type: "user", timestamp: "2026-11-06T13:03:00Z", message: {content: "the checkout total is off by a cent, find out why"}}' > "$d/s1.jsonl"
fixture_repo "$jet"
GIT_AUTHOR_DATE="2026-11-05 10:00" GIT_COMMITTER_DATE="2026-11-05 10:00" git -C "$jet" -c user.email=q@acme.test -c user.name=Q commit -q --allow-empty -m "JET-11 Add login"

# --- the run: from a scratch folder, Monday 2026-11-09 09:00 ---
work="$FIX/work"; mkdir -p "$work"
fixture_claude_md "$work"
NOW=$(perl -MPOSIX -e 'print mktime(0,0,9,9,10,126)')
cat >> "$work/CLAUDE.md" <<MD
For /t-briefing run gather.sh with exactly this prefix, not the one above:
\`VAULT=$VAULT PROJECTS_ROOT=$PROJECTS_ROOT BRIEFING_STATE=$FIX/state BRIEFING_TRANSCRIPTS=$FIX/transcripts BRIEFING_NOW=$NOW GIT_CONFIG_GLOBAL=$FIX/gitconfig TZ=Europe/Berlin PATH=$FIX/bin:$PATH bash <skill dir>/gather.sh\`
This is a test run without Microsoft 365: skip the subagent of step 2 and use these as its lines:
today: 10:00–10:30 Weekly sync [Shop]
Shop: Mail · ann@shop.test · Fri 16:10: asks for the offer draft
unmatched: tom@beta.test (2×) → Shop?
MD
install_skill "$REPO_DIR/skills/briefing" briefing "$work"
run_claude "$work" "/t-briefing" --strict-mcp-config --output-format stream-json --verbose
out=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' <<<"$CLAUDE_OUT")
# the brief is the last text that has the Reply line
brief=$(awk '/^## / { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' <<<"$out")

has() { grep -qF -- "$2" <<<"$brief" && pass "$1" || { fail "$1"; printf '     missing: %s\n' "$2"; }; }
line() { grep -E -- "$2" <<<"$brief" | head -1; }
has "header: today and last workday" "Monday, 9 Nov"
has "header: last workday" "Fri, 6 Nov"
has "today: meeting verbatim" "10:00–10:30 Weekly sync [Shop]"
has "today: note without project keeps its number" "Note 1: call the tax office"
has "shop: note keeps its number" "Note 2: send the offer"
has "shop: next card" "SHP-5"
has "shop: left off" "left off: bugfix/SHP-5"
has "shop: mail verbatim" "Mail · ann@shop.test · Fri 16:10: asks for the offer draft"
has "jet: error fix verbatim" "acli jira auth login"
has "unmatched line" "Unmatched: tom@beta.test (2×) → Shop?"
s=$(line "sentry" "[Ss]entry"); grep -q SHOP-1 <<<"$s" && grep -q SHOP-2 <<<"$s" && pass "shop: sentry new and regressed ids" || fail "shop: sentry new and regressed ids: $s"
grep -qi 'left-pad' <<<"$(line dep '[Dd]ependabot')" && pass "shop: dependabot title" || fail "shop: dependabot title"
grep -qi '^\*\*Did\|Did:' <<<"$brief" && pass "shop: Did line" || fail "shop: Did line"
grep -qx '\*\*Quiet\*\*' <<<"$brief" && fail "quiet project left out" || pass "quiet project left out"
t=$(grep -n '^\*\*Today\*\*' <<<"$brief" | cut -d: -f1); s=$(grep -n '^\*\*Shop\*\*' <<<"$brief" | cut -d: -f1)
[ -n "$t" ] && [ -n "$s" ] && [ "$t" -lt "$s" ] && pass "order: Today before projects" || fail "order: Today before projects"
r=$(line reply '^Reply:')
for o in '"fix all"' '"/dependabot-review"' '"add all"' '"done '; do
  grep -qF "$o" <<<"$r" && pass "reply offers $o" || fail "reply offers $o: $r"
done
[ "$FAILS" -eq 0 ] || { echo "--- brief:"; echo "$brief"; }
done_testing
