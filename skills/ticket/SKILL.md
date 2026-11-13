---
name: ticket
description: Add one ticket card to the project's Obsidian Kanban board, written in the board's own conventions.
argument-hint: "<what the ticket is about>"
disable-model-invocation: true
---

# Ticket

`/ticket <text>` adds one card to the end of `To do` on the project's vault board, shaped like the cards already there, so `/work` can pick it up.

## 0. Arguments

- Only a ticket id (`KEY-12`, `12` or `AB#1234`, nothing else) → stop: "/ticket creates a ticket. To start <id>, run `/work <id>`."
- Empty → ask "What is the ticket about?" and stop.

## 1. Project and board

The vault path and the projects root are set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace them). Run:

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

- `project: none` → stop and print its `reason:`.
- Follow `${CLAUDE_SKILL_DIR}/BOARD.md` to get the board.
- The board is not a vault file → stop: "/ticket writes vault boards only; <project>'s board is <board>."

**Done when:** the board is a vault Kanban file.

## 2. Conventions

Read the whole board file. A **card block** is a `- [ ]` or `- [x]` line starting with `**<KEY>-<n> · <title>**`, plus the tab-indented lines under it. Cards linking a note (`**[[<KEY>-<n> <title>]]**`) count for ids only: their shape is a different format.

From the card blocks, newest ids weighted most, take:

- **Language** of titles and lines (e.g. German on BGH).
- **Title style**: length, verb or noun phrase.
- **Line pattern**: the indented lines most cards carry, in their order, e.g. a description line, `Must · Angebot 3.1.4 · 8 h · Nutzen hoch`, `Goal: …`, `Braucht: …` / `Needs: …`. Note which labels and separators each line uses.
- **Tags** the board uses (`#bug`, `#urgent`, …).

No card blocks on the board → English, one description line, no tags.

**Done when:** you can name the language, the line pattern and the tags, each read off actual cards.

## 3. Next id

`<KEY>` is the lookup's `key:`. No `key:` → ask Quinn for the key and stop.

```bash
grep -rhoE --include='*.md' '\b<KEY>-[0-9]+\b' "<board file>" "$(dirname "<board file>")/tickets" 2>/dev/null \
  | sed 's/.*-//' | sort -n | tail -1
```

Next id: `<KEY>-<printed number + 1>`; nothing printed → `<KEY>-1`.

**Done when:** the id is one higher than every `<KEY>-<n>` on the board and in its `tickets/` folder.

## 4. Draft

Write the card block from the ticket text, in the board's language and line pattern:

```
- [ ] **<id> · <title>** <tags>
	<line>
	<line>
```

- Quinn's text is a rough dictation. Rewrite it as clean board text: correct spelling and grammar, drop filler and repeats, split run-on thoughts into the pattern's lines, and turn questions into what is to be found out ("Find out why /send fails from the app"). Keep every point and its meaning; add none.
- Fill a line only from what the text says; drop the lines it gives nothing for, and list each dropped line as a loose end. Effort, priority, offer item and benefit values come from Quinn, verbatim.
- Dependencies line: the ids the text names, checked to exist on the board; text names none → drop the line.
- Tags: `#bug` when the text describes a defect, `#urgent` when it says urgent, `hotfix` in the title when it says hotfix (`/work` reads these for the branch name). Only tags the board already uses, plus `#bug`.
- Lines start with one tab.

**Done when:** every point of the ticket text is on the card in clean wording, every line traces to the text, and every pattern line without a source is a loose end.

## 5. Write

Read the board file again right before the edit: Quinn edits it in Obsidian at any time. Insert the card block at the end of `## To do` (case-insensitive): after that column's last card, before the blank lines that end the column. Change nothing else. No `To do` column → stop: "no To do column on <board file>".

Print the card block and the loose ends.

**Done when:** the board file has the new card as the last card in `To do`, every other line unchanged, and the card and loose ends are printed.
