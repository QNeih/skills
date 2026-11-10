#!/usr/bin/env bash
# skills/add-context/clean_md.py: escapes and entities removed, code left alone.
. "$(dirname "$0")/lib.sh"
CLEAN="$REPO_DIR/skills/add-context/clean_md.py"
fixture_new
cat > "$FIX/in.md" <<'MD'
# Interview Vertrieb \(10\.11\.2026\)
**Rolle:** Controlling &amp; Marketing<br>**Format:** Teams
- **Teams\-Transkription** nutzen die wenigsten\.
Pfad `C:\Temp\x.md` bleibt
```
a \. b &amp; c
```
Literal backslash: \\
MD
out=$(python3 -I "$CLEAN" "$FIX/in.md")
expect "escaped parens and dots" "$out" "# Interview Vertrieb (10.11.2026)"
expect "entity and br" "$out" "**Rolle:** Controlling & Marketing"
expect "br starts a new line" "$out" "**Format:** Teams"
expect "escaped hyphen" "$out" "- **Teams-Transkription** nutzen die wenigsten."
expect "inline code kept" "$out" 'Pfad `C:\Temp\x.md` bleibt'
expect "fenced code kept" "$out" 'a \. b &amp; c'
expect "escaped backslash" "$out" 'Literal backslash: \'
done_testing
