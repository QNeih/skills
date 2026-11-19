#!/usr/bin/env bash
# The stand-in gh and the wiki fixture builder from lib.sh.
. "$(dirname "$0")/lib.sh"
fixture_new

# stand-in gh: first on PATH, logs each call, answers from canned JSON
fixture_gh
gh_can 'issue list' '[{"number":3,"title":"Three"}]'
gh_can 'issue view 7 --json title' '{"title":"Seven"}'
expect "gh: resolves to the stand-in" "$(command -v gh)" "$FIX/bin/gh"
out=$(gh issue list --repo lisegmbh/wiki --state open)
expect "gh: answers a prefix match" "$out" '[{"number":3,"title":"Three"}]'
expect "gh: exact match wins" "$(gh issue view 7 --json title)" '{"title":"Seven"}'
out=$(gh pr merge 9 --squash); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && pass "gh: unknown call prints nothing and succeeds" || fail "gh: unknown call prints nothing and succeeds"
log=$(gh_calls)
expect "gh: logs a call with its flags" "$log" "issue list --repo lisegmbh/wiki --state open"
expect "gh: logs every call in order" "$(sed -n 3p <<<"$log")" "pr merge 9 --squash"
gh_can 'api graphql' '{"data":1}'
expect "gh: arguments with spaces stay one logged line" "$(gh issue create --title 'a b' >/dev/null; gh_calls | tail -1)" "issue create --title a b"

# wiki fixture: x/{x,wiki} with a project.md
fixture_wiki acme 'board: github' 'close: merge'
[ -d "$PROJECTS_ROOT/acme/acme/.git" ] && [ -d "$PROJECTS_ROOT/acme/wiki/.git" ] \
  && pass "wiki: project and wiki repos" || fail "wiki: project and wiki repos"
pm=$(cat "$PROJECTS_ROOT/acme/wiki/project.md")
expect "wiki: project.md has the settings" "$pm" "board: github"
expect "wiki: project.md second setting" "$pm" "close: merge"
expect "wiki: project.md is front matter" "$(head -1 <<<"$pm")" "---"
git -C "$PROJECTS_ROOT/acme/wiki" log --oneline | grep -q . && pass "wiki: project.md committed" || fail "wiki: project.md committed"

# worktree of the project repo
fixture_wiki_worktree acme ACM-1
wt="$PROJECTS_ROOT/acme/acme/.claude/worktrees/ACM-1"
expect "worktree: on its branch" "$(git -C "$wt" branch --show-current)" "feature/ACM-1"
[ -d "$PROJECTS_ROOT/acme/wiki" ] && pass "worktree: wiki still beside the repo" || fail "worktree: wiki still beside the repo"

# gh repo clone leaves an empty git repo with the origin
gh repo clone QuinnNei/x-wiki "$FIX/cloned" >/dev/null
expect "gh clone: origin is the cloned repo" "$(git -C "$FIX/cloned" remote get-url origin)" "https://github.com/QuinnNei/x-wiki.git"
done_testing
