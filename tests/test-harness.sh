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
mkdir -p "$fake/vault/.git/objects" "$fake/home/.claude/skills" "$fake/projects/skills/.scratch" "$fake/projects/other/.scratch" \
  "$fake/projects/other/other/.claude/worktrees/OT-1/.handoffs" "$fake/projects/flat/.claude/worktrees/FL-1/.scratch"
export REAL_VAULT="$fake/vault" REAL_HOME="$fake/home" REAL_PROJECTS_ROOT="$fake/projects"
guard_start
touch "$fake/projects/skills/.scratch/ok.md"
out=$(guard_check) && pass "guard: quiet run passes" || fail "guard: quiet run passes: $out"
guard_start
touch "$fake/vault/.git/index" "$fake/vault/.git/objects/new"
out=$(guard_check) && pass "guard: a vault sync's .git changes pass" || fail "guard: a vault sync's .git changes pass: $out"
guard_start
touch "$fake/vault/note.md" "$fake/projects/other/.scratch/x.md" "$fake/projects/other/other/.claude/worktrees/OT-1/.handoffs/HANDOFF-OT-1.md" \
  "$fake/projects/flat/.claude/worktrees/FL-1/.scratch/t.md"
out=$(guard_check) && fail "guard: catches writes" || pass "guard: catches writes"
grep -qF "$fake/vault/note.md" <<<"$out" && grep -qF "$fake/projects/other/.scratch/x.md" <<<"$out" \
  && grep -qF "$fake/projects/other/other/.claude/worktrees/OT-1/.handoffs/HANDOFF-OT-1.md" <<<"$out" \
  && grep -qF "$fake/projects/flat/.claude/worktrees/FL-1/.scratch/t.md" <<<"$out" \
  && pass "guard: names the files" || fail "guard: names the files: $out"

# claude lookup: stand-in binaries and a stand-in HOME, on a PATH that holds no real claude
bare=/usr/bin:/bin
mkdir -p "$fake/onpath" "$fake/home/.local/bin" "$fake/nohome"
for d in "$fake/onpath" "$fake/home/.local/bin"; do
  printf '#!/bin/sh\necho "stand-in at $0 got: $*"\n' > "$d/claude"; chmod +x "$d/claude"
done
out=$(HOME="$fake/home" PATH="$fake/onpath:$bare" find_claude)
[ "$out" = "$fake/onpath/claude" ] && pass "lookup: claude on PATH wins" || fail "lookup: claude on PATH wins: $out"
out=$(HOME="$fake/home" PATH="$bare" find_claude)
[ "$out" = "$fake/home/.local/bin/claude" ] && pass "lookup: falls back to ~/.local/bin" || fail "lookup: falls back to ~/.local/bin: $out"
out=$(export HOME="$fake/home" PATH="$bare"; run_claude "$PROJECTS_ROOT/acme" "say hi"; echo "$CLAUDE_OUT")
grep -qF "stand-in at $fake/home/.local/bin/claude got: -p say hi" <<<"$out" \
  && pass "lookup: run_claude runs the claude outside PATH" || fail "lookup: run_claude runs the claude outside PATH: $out"
grep -qF "$fake/home/.local/bin" "$FIX/claude-env.sh" \
  && fail "lookup: the run's PATH leaves ~/.local/bin out" || pass "lookup: the run's PATH leaves ~/.local/bin out"
out=$(export HOME="$fake/nohome" PATH="$bare"; run_claude "$PROJECTS_ROOT/acme" "say hi" 2>&1); code=$?
[ "$code" -eq 2 ] && grep -qF "claude is neither on PATH nor at" <<<"$out" \
  && pass "lookup: no claude stops with exit 2 and a message" || fail "lookup: no claude stops with exit 2 and a message: $code $out"

done_testing
