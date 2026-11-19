#!/usr/bin/env bash
# Wiki create script: turns the wiki template into <vault>/Projects/<Name>/wiki.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/wiki"
fixture_new
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@acme.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@acme.test
fixture_note Acme
W="$VAULT/Projects/Acme/wiki"
git init -q --bare -b main "$FIX/acme-wiki.git"

# new wiki from the template, remote set
out=$(bash "$SK/wiki.sh" "$VAULT" Acme "$FIX/acme-wiki.git")
expect "new: prints the wiki folder" "$out" "created: $W"
for f in CLAUDE.md setup-prompt.md INGEST.md log.md index.md; do
  [ -f "$W/$f" ] && pass "new: $f copied" || fail "new: $f copied"
done
expect "new: one commit" "$(git -C "$W" rev-list --count HEAD)" "1"
expect "new: on main" "$(git -C "$W" branch --show-current)" "main"
expect "new: remote set" "$(git -C "$W" remote get-url origin)" "$FIX/acme-wiki.git"
expect "new: clean tree" "$(git -C "$W" status --porcelain | wc -l | tr -d ' ')" "0"
git -C "$W" check-ignore -q .local && pass "new: wiki ignores the per-person folder file" || fail "new: wiki ignores the per-person folder file"
expect "new: brain ignores the wiki" "$(cat "$VAULT/.gitignore")" 'Projects/*/wiki/'

# re-run changes nothing
echo extra > "$W/page.md"
before=$(git -C "$W" rev-parse HEAD)
out=$(bash "$SK/wiki.sh" "$VAULT" Acme "$FIX/acme-wiki.git")
expect "rerun: says it exists" "$out" "exists: $W"
expect "rerun: history unchanged" "$(git -C "$W" rev-parse HEAD)" "$before"
expect "rerun: files untouched" "$(cat "$W/page.md")" "extra"
expect "rerun: ignore line once" "$(grep -cxF 'Projects/*/wiki/' "$VAULT/.gitignore")" "1"

# ignore line is appended to an existing ignore list, without a wiki line twice
fixture_note Beta
printf '.DS_Store' > "$VAULT/.gitignore"
bash "$SK/wiki.sh" "$VAULT" Beta >/dev/null
expect "ignore: existing entries kept" "$(head -1 "$VAULT/.gitignore")" ".DS_Store"
expect "ignore: wiki line added once" "$(grep -cxF 'Projects/*/wiki/' "$VAULT/.gitignore")" "1"
expect "no remote: none set" "$(git -C "$VAULT/Projects/Beta/wiki" remote | wc -l | tr -d ' ')" "0"

# remote with commits is cloned, not templated
git clone -q "$FIX/acme-wiki.git" "$FIX/seed"
echo "# Pricing" > "$FIX/seed/pricing.md"
git -C "$FIX/seed" add . && git -C "$FIX/seed" commit -q -m "add pricing" && git -C "$FIX/seed" push -q origin main
fixture_note Gamma
out=$(bash "$SK/wiki.sh" "$VAULT" Gamma "$FIX/acme-wiki.git")
expect "clone: prints the wiki folder" "$out" "cloned: $VAULT/Projects/Gamma/wiki"
expect "clone: remote page present" "$(cat "$VAULT/Projects/Gamma/wiki/pricing.md")" "# Pricing"
expect "clone: remote history kept" "$(git -C "$VAULT/Projects/Gamma/wiki" log -1 --format=%s)" "add pricing"
[ -f "$VAULT/Projects/Gamma/wiki/INGEST.md" ] && fail "clone: template not copied" || pass "clone: template not copied"
# unreachable remote: git's message, non-zero, nothing created
fixture_note Delta
out=$(bash "$SK/wiki.sh" "$VAULT" Delta "$FIX/nope.git" 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "bad remote: exits non-zero" || fail "bad remote: exits non-zero"
grep -q 'nope.git' <<<"$out" && pass "bad remote: prints git's message" || fail "bad remote: prints git's message"
[ -e "$VAULT/Projects/Delta/wiki" ] && fail "bad remote: creates nothing" || pass "bad remote: creates nothing"

# empty reachable remote falls through to the template
git init -q --bare -b main "$FIX/empty.git"
fixture_note Eps
out=$(bash "$SK/wiki.sh" "$VAULT" Eps "$FIX/empty.git")
expect "empty remote: template used" "$out" "created: $VAULT/Projects/Eps/wiki"

# missing arguments print a usage line
out=$(bash "$SK/wiki.sh" 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q 'usage:' <<<"$out" && pass "no arguments: usage line" || fail "no arguments: usage line"
done_testing
