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
  git -C "$BRAIN" push -q origin main
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

# wiki folder is left out even when the ignore list lacks the line
mkdir -p "$BRAIN/Projects/Acme/wiki"
echo page > "$BRAIN/Projects/Acme/wiki/page.md"
echo note > "$BRAIN/Projects/Acme/Acme.md"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1
files=$(remote_files)
expect "wiki folder: project note is committed" "$files" "Projects/Acme/Acme.md"
grep -q 'wiki/' <<<"$files" && fail "wiki folder: left out of the commit" || pass "wiki folder: left out of the commit"
expect "wiki folder: ignore line added" "$(cat "$BRAIN/.gitignore")" "Projects/*/wiki/"
echo again > "$BRAIN/again.md"
bash "$SYNC" "$BRAIN" >/dev/null 2>&1
[ "$(grep -cxF 'Projects/*/wiki/' "$BRAIN/.gitignore")" = 1 ] && pass "wiki folder: ignore line added once" || fail "wiki folder: ignore line added once"

# failed push exits non-zero and prints git's message
echo more > "$BRAIN/more.md"
git -C "$BRAIN" remote set-url origin "$FIX/missing.git"
out=$(bash "$SYNC" "$BRAIN" 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "failed push: exits non-zero" || fail "failed push: exits non-zero"
grep -qi 'missing.git' <<<"$out" && pass "failed push: prints git's message" || { fail "failed push: prints git's message"; echo "$out"; }

done_testing
