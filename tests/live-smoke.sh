#!/usr/bin/env bash
# Smoke run of the claude -p harness: a t-probe skill runs the project lookup in a fixture,
# and its gh call reaches the stand-in, not the real gh on the login profile's PATH.
. "$(dirname "$0")/lib.sh"
fixture_new; fixture_gh
fixture_project acme "board: jira" "key: ACM"
P="$PROJECTS_ROOT/acme/acme"
fixture_claude_md "$P"

src="$FIX/src"; mkdir -p "$src"
cp "$REPO_DIR/skills/work/project.sh" "$src/"
cat > "$src/SKILL.md" <<'MD'
---
name: probe
description: Test probe that prints the project lookup.
---
Run `bash ${CLAUDE_SKILL_DIR}/project.sh`, then `gh repo view QuinnNei/acme`. Print the first output verbatim and nothing else.
MD
install_skill "$src" probe "$P"

CLAUDE_MODEL=${CLAUDE_MODEL:-haiku} ALLOWED_TOOLS="Skill,Bash(bash *),Bash(gh *)" run_claude "$P" "/t-probe"
expect "smoke: lookup ran through the skill" "$CLAUDE_OUT" "project: acme"
expect "smoke: key" "$CLAUDE_OUT" "key: ACM"
expect "smoke: gh is the stand-in" "$(gh_calls)" "repo view QuinnNei/acme"
done_testing
