#!/usr/bin/env bash
# Brain sync script: commits and pushes a brain, leaves wiki folders out.
. "$(dirname "$0")/lib.sh"
SYNC="$REPO_DIR/skills/wiki/brain-sync.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@acme.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@acme.test

# new_brain: fresh brain with a bare remote and one pushed commit; sets BRAIN, REMOTE
new_brain() {
  fixture_new
  REMOTE="$FIX/remote.git"; BRAIN="$FIX/brain"
  git init -q --bare -b main "$REMOTE"
  fixture_repo "$BRAIN" "$REMOTE"
  git -C "$BRAIN" push -q -u origin main
}
remote_count() { git -C "$REMOTE" rev-list --count main; }
remote_files() { git -C "$REMOTE" ls-tree -r --name-only main; }

new_brain
echo "hello" > "$BRAIN/Briefing notes.md"
out=$(bash "$SYNC" "$BRAIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "changed brain: exits 0" || fail "changed brain: exits 0 ($out)"
expect "changed brain: file is on the remote" "$(remote_files)" "Briefing notes.md"
expect "changed brain: commit message is the date" "$(git -C "$REMOTE" log -1 --format=%s main)" "$(date +%F)"

before=$(remote_count)
bash "$SYNC" "$BRAIN" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "no change: exits 0" || fail "no change: exits 0"
[ "$(remote_count)" = "$before" ] && pass "no change: no new commit" || fail "no change: no new commit"

# wiki folder is never part of the commit, with or without an ignore line
mkdir -p "$BRAIN/Projects/Acme/wiki"
echo page > "$BRAIN/Projects/Acme/wiki/page.md"
echo note > "$BRAIN/Projects/Acme/Acme.md"
printf 'x' > "$BRAIN/.gitignore"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1
files=$(remote_files)
expect "wiki folder: project note is committed" "$files" "Projects/Acme/Acme.md"
grep -q 'wiki' <<<"$files" && fail "wiki folder: left out of the commit" || pass "wiki folder: left out of the commit"
expect "wiki folder: ignore file not edited" "$(cat "$BRAIN/.gitignore")" "x"

# a wiki folder that is itself a git repo is left out too
git init -q -b main "$BRAIN/Projects/Acme/wiki"
git -C "$BRAIN/Projects/Acme/wiki" commit -q --allow-empty -m w
echo again > "$BRAIN/again.md"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1
files=$(remote_files)
expect "wiki repo: other file is committed" "$files" "again.md"
grep -q 'wiki' <<<"$files" && fail "wiki repo: left out of the commit" || pass "wiki repo: left out of the commit"

# nothing changed and nothing unpushed: the network is not touched
git -C "$BRAIN" remote set-url origin "$FIX/missing.git"
out=$(bash "$SYNC" "$BRAIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "nothing to push: exits 0 offline" || fail "nothing to push: exits 0 offline ($out)"
git -C "$BRAIN" remote set-url origin "$REMOTE"

# failed push exits non-zero and prints git's message
echo more > "$BRAIN/more.md"
git -C "$BRAIN" remote set-url origin "$FIX/missing.git"
out=$(bash "$SYNC" "$BRAIN" 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "failed push: exits non-zero" || fail "failed push: exits non-zero"
grep -qi 'missing.git' <<<"$out" && pass "failed push: prints git's message" || { fail "failed push: prints git's message"; echo "$out"; }

# the commit left by the failed push is pushed on the next run
git -C "$BRAIN" remote set-url origin "$REMOTE"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "unpushed commit: next run exits 0" || fail "unpushed commit: next run exits 0"
expect "unpushed commit: reaches the remote" "$(remote_files)" "more.md"

# a branch without upstream is pushed
git -C "$BRAIN" checkout -q -b side
echo s > "$BRAIN/side.md"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1
expect "no upstream: branch is pushed" "$(git -C "$REMOTE" ls-tree -r --name-only side)" "side.md"

done_testing
