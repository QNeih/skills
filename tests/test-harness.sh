#!/usr/bin/env bash
# The claude -p harness parts that run without claude: skill install, fixture CLAUDE.md, guard.
. "$(dirname "$0")/lib.sh"
fixture_new

src=$(mktemp -d /tmp/skills-test-src.XXXXXX); trap 'rm -rf "$FIX" "$src"' EXIT
printf -- '---\nname: probe\ndescription: test\n---\nBody name: probe\n' > "$src/SKILL.md"
echo helper > "$src/helper.sh"
fixture_repo "$PROJECTS_ROOT/acme"
fixture_claude_md "$PROJECTS_ROOT/acme"
install_skill "$src" probe "$PROJECTS_ROOT/acme"
t="$PROJECTS_ROOT/acme/.claude/skills/t-probe"
expect "install: name rewritten" "$(cat "$t/SKILL.md")" "name: t-probe"
expect "install: body kept" "$(cat "$t/SKILL.md")" "Body name: probe"
[ -f "$t/helper.sh" ] && pass "install: skill files copied" || fail "install: skill files copied"
grep -qF "$VAULT" "$PROJECTS_ROOT/acme/CLAUDE.md" && grep -qF "$PROJECTS_ROOT" "$PROJECTS_ROOT/acme/CLAUDE.md" \
  && pass "fixture CLAUDE.md names fixture paths" || fail "fixture CLAUDE.md names fixture paths"

# Guard: stand-in real dirs, so nothing real is touched
fake=$(cd "$src" && pwd -P)
mkdir -p "$fake/vault" "$fake/home/.claude/skills" "$fake/home/.claude/briefing" "$fake/projects/skills/.scratch" "$fake/projects/other/.scratch"
export REAL_VAULT="$fake/vault" REAL_HOME="$fake/home" REAL_PROJECTS_ROOT="$fake/projects"
guard_start
touch "$fake/projects/skills/.scratch/ok.md"
out=$(guard_check) && pass "guard: quiet run passes" || fail "guard: quiet run passes: $out"
guard_start
touch "$fake/vault/note.md" "$fake/projects/other/.scratch/x.md"
out=$(guard_check) && fail "guard: catches writes" || pass "guard: catches writes"
grep -qF "$fake/vault/note.md" <<<"$out" && grep -qF "$fake/projects/other/.scratch/x.md" <<<"$out" \
  && pass "guard: names the files" || fail "guard: names the files: $out"

done_testing
