#!/usr/bin/env bash
# Settings script (settings.sh): get reads one front matter line, set changes exactly one, publish
# commits the settings file alone on the default branch and pushes it.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work"
fixture_new
S() { bash "$SK/settings.sh" "$@"; }
G() { git -C "$1" -c user.name=t -c user.email=t@acme.test "${@:2}"; }
settings() { cat "$1/.claude/project.md"; }
# fixture_origin <checkout>: a bare origin the checkout's current branch is pushed to
fixture_origin() {
  git init -q --bare --template= -b main "$FIX/origin-$(basename "$1").git"
  git -C "$1" remote add origin "$FIX/origin-$(basename "$1").git"
  git -C "$1" push -q -u origin HEAD
}

# get: value without its quotes, nothing for a missing line or file, the main checkout from a worktree
P="$PROJECTS_ROOT/acme/acme"
fixture_project acme 'board: github' 'project: 7' 'sentry: "acme/web, acme/api"' "close: 'Done'"
expect "get: plain value" "$(S get "$P" project)" "7"
expect "get: double quotes stripped" "$(S get "$P" sentry)" "acme/web, acme/api"
expect "get: single quotes stripped" "$(S get "$P" close)" "Done"
expect "get: missing line prints nothing" "[$(S get "$P" key)]" "[]"
mkdir -p "$PROJECTS_ROOT/nofile"
expect "get: missing file prints nothing" "[$(S get "$PROJECTS_ROOT/nofile" key)]" "[]"
fixture_worktree "$P" ACM-1
printf -- '---\nproject: 99\n---\n' > "$P/.claude/worktrees/ACM-1/.claude/project.md"
expect "get: from a worktree reads the main checkout" "$(S get "$P/.claude/worktrees/ACM-1" project)" "7"
mkdir -p "$P/sub/dir"
expect "get: from a subfolder reads the main checkout" "$(S get "$P/sub/dir" project)" "7"
mkdir -p "$FIX/fm/.claude"; printf -- '---\nboard: github\n---\nproject: 9\n' > "$FIX/fm/.claude/project.md"
expect "get: only the front matter counts" "[$(S get "$FIX/fm" project)]" "[]"

# set: exactly one settings line changes
printf -- '---\nboard: github\nproject: 7\nsentry: acme-web\nclose: merge\n---\nbody stays\n' > "$P/.claude/project.md"
before=$(settings "$P")
out=$(S set "$P" close pr)
after=$(settings "$P")
expect "set: prints the file" "$out" "saved: close in $P/.claude/project.md"
expect "set: line replaced" "$after" "close: pr"
[ "$(diff <(echo "$before") <(echo "$after") | grep -c '^[<>]')" = 2 ] && pass "set: exactly one line differs" || fail "set: exactly one line differs"
S set "$P" key SKL >/dev/null
expect "set: missing line added" "$(settings "$P")" "key: SKL"
expect "set: body kept" "$(settings "$P")" "body stays"
[ "$(grep -c '^key:' "$P/.claude/project.md")" = 1 ] && pass "set: one key line" || fail "set: one key line"
S set "$P" close 'a\nb "c"' >/dev/null
expect "set: backslashes and quotes kept as given" "$(settings "$P")" 'close: a\nb "c"'
expect "set: commits nothing" "$(G "$P" status --porcelain)" " M .claude/project.md"
# a newline in KEY or VALUE would write extra front matter lines: refused, file unchanged
before=$(settings "$P")
out=$(S set "$P" close $'pr\nowner: evil' 2>&1) && rc=0 || rc=$?
[ "$rc" != 0 ] && pass "set: a newline in VALUE fails" || fail "set: a newline in VALUE fails"
expect "set: says why" "$out" "settings.sh: KEY and VALUE must each be one line"
expect "set: VALUE with a newline leaves the file unchanged" "$(settings "$P")" "$before"
S set "$P" $'ke\ny' v >/dev/null 2>&1 && fail "set: a newline in KEY fails" || pass "set: a newline in KEY fails"
expect "set: KEY with a newline leaves the file unchanged" "$(settings "$P")" "$before"
S publish "$P" close $'pr\nowner: evil' >/dev/null 2>&1 && fail "publish: a newline in VALUE fails" || pass "publish: a newline in VALUE fails"
expect "publish: VALUE with a newline leaves the file unchanged" "$(settings "$P")" "$before"
# set creates the settings file: a board that is a link needs no GitHub Project
P2="$PROJECTS_ROOT/eta"
fixture_repo "$P2"
S set "$P2" board "https://boards.acme.test/org/eta" >/dev/null
expect "set: creates the settings file" "$(settings "$P2")" "board: https://boards.acme.test/org/eta"
expect "set: front matter" "$(head -1 "$P2/.claude/project.md")" "---"

# publish on the default branch: the settings file alone is committed and pushed
P3="$PROJECTS_ROOT/pub"
fixture_project_flat pub 'board: github'
fixture_origin "$P3"
echo "other work" > "$P3/other.txt"; G "$P3" add other.txt
out=$(S publish "$P3" key PUB)
expect "publish: says published" "$out" "published: $P3/.claude/project.md"
expect "publish: the line is saved" "$(settings "$P3")" "key: PUB"
expect "publish: commit holds only the settings file" "$(G "$P3" show --name-only --format= HEAD)" ".claude/project.md"
expect "publish: other staged work stays staged" "$(G "$P3" status --porcelain)" "A  other.txt"
expect "publish: origin has the commit" "$(git --git-dir="$FIX/origin-pub.git" log -1 --format=%H main)" "$(G "$P3" rev-parse HEAD)"
# nothing changed → nothing to publish; a hand edit is published without KEY VALUE
out=$(S publish "$P3")
expect "publish: unchanged file" "$out" "nothing to publish: $P3/.claude/project.md"
S set "$P3" owner Org >/dev/null
out=$(S publish "$P3")
expect "publish without a line: publishes the pending change" "$out" "published: $P3/.claude/project.md"
expect "publish without a line: origin has it" "$(git --git-dir="$FIX/origin-pub.git" show main:.claude/project.md)" "owner: Org"
# from a ticket worktree it publishes the main checkout's file
fixture_worktree "$P3" PUB-1
out=$(S publish "$P3/.claude/worktrees/PUB-1" close pr)
expect "publish: from a worktree publishes the main checkout" "$out" "published: $P3/.claude/project.md"
expect "publish: from a worktree the commit is on the main checkout's branch" "$(G "$P3" log -1 --format=%s main)" "Update project settings"
expect "publish: from a worktree the commit holds only the settings file" "$(G "$P3" show --name-only --format= main)" ".claude/project.md"
expect "publish: from a worktree the line is in the commit" "$(G "$P3" show main:.claude/project.md)" "close: pr"
# the file is new: it is added by the commit
P4="$PROJECTS_ROOT/fresh"
fixture_repo "$P4"; fixture_origin "$P4"
out=$(S publish "$P4" board github)
expect "publish: a new settings file is committed" "$out" "published: $P4/.claude/project.md"
expect "publish: the new file is tracked" "$(G "$P4" ls-files .claude/project.md)" ".claude/project.md"

# publish on another branch: file saved, nothing committed, could not fix with the cause
P5="$PROJECTS_ROOT/branchy"
fixture_project_flat branchy 'board: github'
fixture_origin "$P5"
G "$P5" checkout -q -b feature/X-1
head=$(G "$P5" rev-parse HEAD)
out=$(S publish "$P5" key BRN) && rc=0 || rc=$?
expect "other branch: could not fix names the branches" "$out" "could not fix: $P5 is on feature/X-1, not the default branch main; $P5/.claude/project.md stays uncommitted"
[ "$rc" = 1 ] && pass "other branch: exits 1" || fail "other branch: exits 1 (got $rc)"
expect "other branch: file keeps the line" "$(settings "$P5")" "key: BRN"
[ "$(G "$P5" rev-parse HEAD)" = "$head" ] && pass "other branch: no commit" || fail "other branch: no commit"
G "$P5" checkout -q --detach
out=$(S publish "$P5" key BRN2) && rc=0 || rc=$?
expect "detached head: could not fix" "$out" "could not fix: $P5 is on a detached HEAD, not the default branch main; $P5/.claude/project.md stays uncommitted"
[ "$(G "$P5" rev-parse HEAD)" = "$head" ] && pass "detached head: no commit" || fail "detached head: no commit"

# publish when the push fails: the file stays as saved and uncommitted
P6="$PROJECTS_ROOT/nopush"
fixture_project_flat nopush 'board: github'
fixture_origin "$P6"
G "$P6" remote set-url origin "$FIX/does-not-exist.git"
echo "other work" > "$P6/other.txt"; G "$P6" add other.txt
head=$(G "$P6" rev-parse HEAD)
out=$(S publish "$P6" key NOP) && rc=0 || rc=$?
grep -q "^could not fix: push of main failed: .*; $P6/.claude/project.md stays uncommitted$" <<<"$out" && pass "push fails: could not fix with the cause" || { fail "push fails: could not fix with the cause"; echo "$out"; }
[ "$rc" = 1 ] && pass "push fails: exits 1" || fail "push fails: exits 1 (got $rc)"
expect "push fails: file keeps the line" "$(settings "$P6")" "key: NOP"
[ "$(G "$P6" rev-parse HEAD)" = "$head" ] && pass "push fails: commit undone" || fail "push fails: commit undone"
expect "push fails: file is an unstaged modification" "$(G "$P6" status --porcelain)" " M .claude/project.md"
expect "push fails: an unrelated staged file is still staged" "$(G "$P6" status --porcelain)" "A  other.txt"
G "$P6" reset -q -- other.txt; rm "$P6/other.txt"
G "$P6" remote set-url origin "$FIX/origin-nopush.git"
expect "push fails: a later publish succeeds" "$(S publish "$P6")" "published: $P6/.claude/project.md"

# publish when the commit fails (a rejecting pre-commit hook): could not fix, file unstaged
P8="$PROJECTS_ROOT/hooked"
fixture_project_flat hooked 'board: github'
fixture_origin "$P8"
mkdir -p "$P8/.git/hooks"; printf '#!/bin/sh\necho "hook says no" >&2\nexit 1\n' > "$P8/.git/hooks/pre-commit"; chmod +x "$P8/.git/hooks/pre-commit"
echo "other work" > "$P8/other.txt"; G "$P8" add other.txt
head=$(G "$P8" rev-parse HEAD)
out=$(S publish "$P8" key HOK) && rc=0 || rc=$?
expect "commit fails: could not fix with the cause" "$out" "could not fix: commit failed: hook says no; $P8/.claude/project.md stays uncommitted"
[ "$rc" = 1 ] && pass "commit fails: exits 1" || fail "commit fails: exits 1 (got $rc)"
expect "commit fails: file keeps the line" "$(settings "$P8")" "key: HOK"
[ "$(G "$P8" rev-parse HEAD)" = "$head" ] && pass "commit fails: no commit" || fail "commit fails: no commit"
expect "commit fails: file is an unstaged modification" "$(G "$P8" status --porcelain)" " M .claude/project.md"
expect "commit fails: an unrelated staged file is still staged" "$(G "$P8" status --porcelain)" "A  other.txt"

# publish with a failing push when the settings commit would be the repo's first commit
P9="$PROJECTS_ROOT/unborn"
mkdir -p "$P9"; git init -q -b main --template= "$P9"
git init -q --bare --template= -b main "$FIX/origin-unborn.git"
git -C "$P9" remote add origin "$FIX/does-not-exist.git"
git -C "$P9" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
out=$(S publish "$P9" board github) && rc=0 || rc=$?
grep -q "^could not fix: push of main failed: .*; $P9/.claude/project.md stays uncommitted$" <<<"$out" && pass "first commit, push fails: could not fix" || { fail "first commit, push fails: could not fix"; echo "$out"; }
[ "$rc" = 1 ] && pass "first commit, push fails: exits 1" || fail "first commit, push fails: exits 1 (got $rc)"
git -C "$P9" rev-parse -q --verify HEAD >/dev/null && fail "first commit, push fails: commit undone" || pass "first commit, push fails: commit undone"
expect "first commit, push fails: file is untracked again" "$(G "$P9" status --porcelain)" "?? .claude/"
expect "first commit, push fails: file keeps the line" "$(settings "$P9")" "board: github"
git -C "$P9" remote set-url origin "$FIX/origin-unborn.git"
expect "first commit: a later publish succeeds" "$(S publish "$P9")" "published: $P9/.claude/project.md"

# default branch: what origin/HEAD names decides, whatever its name; else main, else master
P10="$PROJECTS_ROOT/trunky"
fixture_project_flat trunky 'board: github'
G "$P10" branch -m trunk
fixture_origin "$P10"
G "$P10" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
expect "origin/HEAD: publishes from the branch it names" "$(S publish "$P10" key TRK)" "published: $P10/.claude/project.md"
P11="$PROJECTS_ROOT/mainish"
fixture_project_flat mainish 'board: github'
fixture_origin "$P11"
G "$P11" update-ref refs/remotes/origin/trunk HEAD
G "$P11" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
out=$(S publish "$P11" key MNI) && rc=0 || rc=$?
expect "origin/HEAD: main is not the default when it names another branch" "$out" "could not fix: $P11 is on main, not the default branch trunk; $P11/.claude/project.md stays uncommitted"
P12="$PROJECTS_ROOT/masterish"
fixture_project_flat masterish 'board: github'
G "$P12" branch -m master
fixture_origin "$P12"
expect "master fallback: publishes from master" "$(S publish "$P12" key MST)" "published: $P12/.claude/project.md"

# no git: saved, not published
P7="$FIX/plain/proj"; mkdir -p "$P7"
out=$(S publish "$P7" board jira)
expect "no git: not published" "$out" "not published: $P7 is no git repository"
expect "no git: file saved" "$(settings "$P7")" "board: jira"

# usage
S bogus "$P" >/dev/null 2>&1 && fail "unknown call fails" || pass "unknown call fails"

done_testing
