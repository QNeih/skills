---
name: note
description: Save a to-do to the briefing notes, tagged with the current project. Use when the user types "/note" followed by the text.
---

# Note

Appends `- [ ] <date> <text>` to `<vault>/Briefing notes.md`, plus `[[<project>]]` when run inside a project. `/briefing` shows the open ones.

The vault path and the projects root are set in `~/.claude/CLAUDE.md`.

## 1. Text

The text after `/note` is the note. Empty → ask "What should the note say?" and stop.

**Done when:** you have the text, or you asked for it.

## 2. Append

Run, with the text verbatim in the heredoc:

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/note.sh <<'EOF'
<text>
EOF
```

It looks up the project, appends the line (creating the file if missing) and prints it. An `error:` line → show it and stop.

**Done when:** the printed line is shown to the user.
