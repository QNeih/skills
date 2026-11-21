#!/usr/bin/env bash
# work/fetch_attachments.py: saves a Jira issue's attachments as <NN>-<sanitized-filename>, skips the
# ones over --max-mb, and stops with a setup hint when the Keychain item is missing.
# Offline: the site is a file:// folder and a fake `security` on PATH stands in for the Keychain.
. "$(dirname "$0")/lib.sh"
fixture_new
fetch="$REPO_DIR/skills/work/fetch_attachments.py"
site="$FIX/jira" files="$FIX/files" out_dir="$FIX/out"
mkdir -p "$FIX/bin" "$site/rest/api/3/issue" "$files"
export PATH="$FIX/bin:$PATH"

# fake security: answers the jira-attachments item, or fails when $FIX/no-keychain exists
cat > "$FIX/bin/security" <<SEC
#!/usr/bin/env bash
[ -e "$FIX/no-keychain" ] && exit 44
case " \$* " in
  *" -w "*) echo secret-token ;;
  *) echo '    "acct"<blob>="t@acme.test"' ;;
esac
SEC
chmod +x "$FIX/bin/security"

printf 'first\n' > "$files/a.txt"
printf 'second\n' > "$files/b.png"
printf 'third\n' > "$files/c.mov"
# the script asks for <site>/rest/api/3/issue/<KEY>?fields=attachment; a file URL keeps the query in the path
cat > "$site/rest/api/3/issue/ACM-1?fields=attachment" <<JSON
{"fields": {"attachment": [
  {"filename": "spec notes (v2).txt", "size": 6, "mimeType": "text/plain", "content": "file://$files/a.txt"},
  {"filename": "huge.mov", "size": 31457280, "mimeType": "video/quicktime", "content": "file://$files/c.mov"},
  {"filename": "screen.png", "size": 7, "mimeType": "image/png", "content": "file://$files/b.png"}
]}}
JSON

out=$(python3 -I "$fetch" --site "file://$site/" --cloud-id c1 ACM-1 "$out_dir" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || { fail "exit 0, got $rc"; echo "$out"; }
expect "counts the attachments" "$out" "3 attachment(s)"
expect "saves with number and sanitized name" "$out" "saved   $out_dir/01-spec-notes-v2-.txt  text/plain  0 KB"
expect "skips one over --max-mb" "$out" "skipped 02-huge.mov  video/quicktime  30720 KB  (over 20 MB, rerun with --max-mb)"
expect "numbers keep counting after a skip" "$out" "saved   $out_dir/03-screen.png  image/png  0 KB"
[ "$(cat "$out_dir/01-spec-notes-v2-.txt" 2>/dev/null)" = first ] && pass "saved file has the attachment's content" || fail "saved file has the attachment's content"
[ ! -e "$out_dir/02-huge.mov" ] && pass "skipped file is not written" || fail "skipped file is not written"
! grep -q secret-token <<<"$out" && pass "token is never printed" || fail "token is never printed"

out=$(python3 -I "$fetch" --site "file://$site/" --cloud-id c1 --max-mb 40 ACM-1 "$FIX/out2" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "--max-mb 40: exit 0" || { fail "--max-mb 40: exit 0, got $rc"; echo "$out"; }
expect "--max-mb 40 saves the big one too" "$out" "saved   $FIX/out2/02-huge.mov  video/quicktime  30720 KB"

touch "$FIX/no-keychain"
out=$(python3 -I "$fetch" --site "file://$site/" --cloud-id c1 ACM-1 "$FIX/out3" 2>&1); rc=$?
[ $rc -eq 1 ] && pass "no Keychain item: exit 1" || fail "no Keychain item: exit 1, got $rc"
expect "no Keychain item: setup hint" "$out" "error: Keychain item 'jira-attachments' missing; run: security add-generic-password -s jira-attachments -a <jira-email> -w"
[ ! -e "$FIX/out3" ] && pass "no Keychain item: nothing written" || fail "no Keychain item: nothing written"
done_testing
