#!/usr/bin/env bash
# Smoke run of the claude -p harness: a t-probe skill runs the project lookup in a fixture.
. "$(dirname "$0")/lib.sh"
fixture_new
fixture_note Acme
printf -- '- [ ] **ACM-1 · First card**\n' > "$VAULT/Projects/Acme/Acme Board.md"
fixture_repo "$PROJECTS_ROOT/acme"
fixture_claude_md "$PROJECTS_ROOT/acme"

src="$FIX/src"; mkdir -p "$src"
cp "$REPO_DIR/skills/work/project.sh" "$src/"
cat > "$src/SKILL.md" <<'MD'
---
name: probe
description: Test probe that prints the project lookup.
---
Run `bash ${CLAUDE_SKILL_DIR}/project.sh` with `VAULT` and `PROJECTS_ROOT` set as CLAUDE.md says. Print its output verbatim and nothing else.
MD
install_skill "$src" probe "$PROJECTS_ROOT/acme"

CLAUDE_MODEL=${CLAUDE_MODEL:-haiku} ALLOWED_TOOLS="Skill,Bash(VAULT=*),Bash(bash *)" run_claude "$PROJECTS_ROOT/acme" "/t-probe"
expect "smoke: lookup ran through the skill" "$CLAUDE_OUT" "project: Acme"
expect "smoke: key" "$CLAUDE_OUT" "key: ACM"
done_testing
