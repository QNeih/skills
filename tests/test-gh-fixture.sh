#!/usr/bin/env bash
# The stand-in gh and the project fixture builders from lib.sh.
. "$(dirname "$0")/lib.sh"
fixture_new

# stand-in gh: first on PATH, logs each call, answers from canned JSON
fixture_gh
gh_can 'issue list' '[{"number":3,"title":"Three"}]'
gh_can 'issue view 7 --json title' '{"title":"Seven"}'
expect "gh: resolves to the stand-in" "$(command -v gh)" "$FIX/bin/gh"
out=$(gh issue list --repo lisegmbh/acme --state open)
expect "gh: answers a prefix match" "$out" '[{"number":3,"title":"Three"}]'
expect "gh: exact match wins" "$(gh issue view 7 --json title)" '{"title":"Seven"}'
out=$(gh pr merge 9 --squash); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && pass "gh: unknown call prints nothing and succeeds" || fail "gh: unknown call prints nothing and succeeds"
log=$(gh_calls)
expect "gh: logs a call with its flags" "$log" "issue list --repo lisegmbh/acme --state open"
expect "gh: logs every call in order" "$(sed -n 3p <<<"$log")" "pr merge 9 --squash"
gh_can 'api graphql' '{"data":1}'
expect "gh: arguments with spaces stay one logged line" "$(gh issue create --title 'a b' >/dev/null; gh_calls | tail -1)" "issue create --title a b"

# a body passed as a file is logged as its text, like a body passed as text
closes='^Closes QuinnNei/acme#13( --[a-z].*)?$'   # the body's last line, then at most further flags
printf 'Summary\n\nCloses QuinnNei/acme#13\n' > "$FIX/body.md"
printf 'Closes QuinnNei/acme#13\n\nSummary\n' > "$FIX/body-wrong.md"
: > "$GH_LOG"; gh pr create --title T --body "$(cat "$FIX/body.md")" --base main
text_log=$(gh_calls)
: > "$GH_LOG"; gh pr create --title T --body-file "$FIX/body.md" --base main
expect "gh: --body-file logs the same as --body" "$(gh_calls)" "$(tail -1 <<<"$text_log")"
[ "$(gh_calls | sed 's/--body-file/--body/')" = "$text_log" ] && pass "gh: --body-file logs the whole body in place of the path" || fail "gh: --body-file logs the whole body in place of the path"
for form in "--body-file $FIX/body.md" "--body-file=$FIX/body.md" "-F $FIX/body.md"; do
  : > "$GH_LOG"; gh pr edit 7 $form
  name="gh: ${form%%[ =]*} on pr edit logs the body's last line"; [ "${form#*=}" = "$form" ] || name="$name (= form)"
  gh_calls | grep -qE "$closes" && pass "$name" || { fail "$name"; gh_calls; }
done
: > "$GH_LOG"; gh pr create --title T --body-file - < "$FIX/body.md"
gh_calls | grep -qE "$closes" && pass "gh: a body on stdin is logged" || { fail "gh: a body on stdin is logged"; gh_calls; }
: > "$GH_LOG"; gh pr create --title T --body-file "$FIX/body-wrong.md"
gh_calls | tail -1 | grep -qE "$closes" && fail "gh: a body file ending in another line does not end the log with the Closes line" || pass "gh: a body file ending in another line does not end the log with the Closes line"
gh_can 'pr create' 'https://github.com/QuinnNei/acme/pull/7'
expect "gh: a call with a body file still gets its canned answer" "$(gh pr create --body-file "$FIX/body.md")" "https://github.com/QuinnNei/acme/pull/7"
: > "$GH_LOG"; gh api graphql -F owner=QuinnNei -F name=acme >/dev/null
expect "gh: api fields after -F are logged unchanged" "$(gh_calls)" "api graphql -F owner=QuinnNei -F name=acme"

# gh_seq: matching calls get the answers one after the other, the last repeats
gh_seq 'issue create' 'url/1' 'url/2'
expect "gh_seq: first call" "$(gh issue create --title a)" "url/1"
expect "gh_seq: second call" "$(gh issue create --title b)" "url/2"
expect "gh_seq: the last answer repeats" "$(gh issue create --title c)" "url/2"

# project fixture, nested layout: x/x with the settings file committed in it
fixture_project acme 'board: github' 'close: merge'
P="$PROJECTS_ROOT/acme/acme"
[ -d "$P/.git" ] && pass "project: checkout in a folder of its name" || fail "project: checkout in a folder of its name"
pm=$(cat "$P/.claude/project.md")
expect "project: settings file has the settings" "$pm" "board: github"
expect "project: second setting" "$pm" "close: merge"
expect "project: settings are front matter" "$(head -1 <<<"$pm")" "---"
[ -z "$(git -C "$P" status --porcelain)" ] && git -C "$P" ls-files --error-unmatch .claude/project.md >/dev/null 2>&1 \
  && pass "project: settings file committed" || fail "project: settings file committed"

# flat layout: the folder under the projects root is the checkout
fixture_project_flat solo 'project: 3'
[ -d "$PROJECTS_ROOT/solo/.git" ] && pass "flat: checkout under the projects root" || fail "flat: checkout under the projects root"
expect "flat: settings file" "$(cat "$PROJECTS_ROOT/solo/.claude/project.md")" "project: 3"

# settings for a folder without git are written, not committed
mkdir -p "$PROJECTS_ROOT/docs"
fixture_settings "$PROJECTS_ROOT/docs" 'board: jira'
expect "no git: settings file" "$(cat "$PROJECTS_ROOT/docs/.claude/project.md")" "board: jira"

# ticket worktree of the checkout
fixture_worktree "$P" ACM-1
wt="$P/.claude/worktrees/ACM-1"
expect "worktree: on its branch" "$(git -C "$wt" branch --show-current)" "feature/ACM-1"
[ -f "$wt/.claude/project.md" ] && pass "worktree: carries the committed settings file" || fail "worktree: carries the committed settings file"
done_testing
