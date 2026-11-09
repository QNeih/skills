#!/usr/bin/env bash
# Fails when copies of one shared file (same name in several skill folders) differ.
# SKILL.md is per skill and skipped.
cd "$(dirname "$0")/../skills" || exit 1
rc=0
for name in $(find . -type f ! -name SKILL.md -exec basename {} \; | sort | uniq -d); do
  first=
  while IFS= read -r f; do
    if [ -z "$first" ]; then first=$f
    elif ! cmp -s "$first" "$f"; then echo "FAIL shared copy differs: $f vs $first"; rc=1
    fi
  done < <(find . -type f -name "$name" | sort)
  [ $rc -eq 0 ] && echo "ok   shared copies of $name match"
done
exit $rc
