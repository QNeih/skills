#!/usr/bin/env bash
# Settings script (settings.sh): get reads one front matter line, set changes exactly one, publish
# commits the settings file alone on the default branch and pushes it.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work"
fixture_new
S() { bash "$SK/settings.sh" "$@"; }
G() { git -C "$1" -c user.name=t -c user.email=t@acme.test "${@:2}"; }
settings() { cat "$1/.claude/project.md"; }
# fixture_origin <checkout>: a bare origin the checkout's main branch is pushed to
fixture_origin() {
  git init -q --bare --template= -b main "$FIX/origin-$(basename "$1").git"
  git -C "$1" remote add origin "$FIX/origin-$(basename "$1").git"
  git -C "$1" push -q -u origin main
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

# publish when the push fails: the file stays as saved and uncommitted
P6="$PROJECTS_ROOT/nopush"
fixture_project_flat nopush 'board: github'
fixture_origin "$P6"
G "$P6" remote set-url origin "$FIX/does-not-exist.git"
head=$(G "$P6" rev-parse HEAD)
out=$(S publish "$P6" key NOP) && rc=0 || rc=$?
grep -q "^could not fix: push of main failed: .*; $P6/.claude/project.md stays uncommitted$" <<<"$out" && pass "push fails: could not fix with the cause" || { fail "push fails: could not fix with the cause"; echo "$out"; }
[ "$rc" = 1 ] && pass "push fails: exits 1" || fail "push fails: exits 1 (got $rc)"
expect "push fails: file keeps the line" "$(settings "$P6")" "key: NOP"
[ "$(G "$P6" rev-parse HEAD)" = "$head" ] && pass "push fails: commit undone" || fail "push fails: commit undone"
expect "push fails: file is a plain modification" "$(G "$P6" status --porcelain)" " M .claude/project.md"
G "$P6" remote set-url origin "$FIX/origin-nopush.git"
expect "push fails: a later publish succeeds" "$(S publish "$P6")" "published: $P6/.claude/project.md"

# no git: saved, not published
P7="$FIX/plain/proj"; mkdir -p "$P7"
out=$(S publish "$P7" board jira)
expect "no git: not published" "$out" "not published: $P7 is no git repository"
expect "no git: file saved" "$(settings "$P7")" "board: jira"

# usage
S bogus "$P" >/dev/null 2>&1 && fail "unknown call fails" || pass "unknown call fails"

done_testing
