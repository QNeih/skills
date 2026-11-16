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
- Starts with `todo:` → the rest is a to-do's text (a line of `<vault>/Briefing notes.md`, see `GLOSSARY.md`); step 3a applies. Empty after `todo:` → ask for it and stop.
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

## 3a. Grill open questions

Before writing, find the **open questions**: what the text leaves open whose answer would change the work, such as which parts of the project it covers, which tool to use, or where it runs. Example: "add linter to project" leaves open which folders the linter checks, which linter, and whether it runs in `test.sh` or before `/send`. Ask only what the ticket's session could not settle while working.

Also compare the text with the board's cards (any column): an overlap with a card is an open question.

- `todo:` → always grill, at least to confirm the card's scope; keep the original to-do text for step 6.
- Else, no open questions → go on to step 4.
- Else → grill Quinn: one question per message, each with your recommended answer; wait for each answer.

Quinn's answers refine the text into the ticket text for step 4.

**Done when:** every open question is answered, and on `todo:` Quinn confirmed the scope.

## 4. Draft

Write the card block from the ticket text, in the board's language and line pattern:

```
- [ ] **<id> · <title>** <tags>
	<line>
	<line>
```

- Quinn's text is a rough dictation. Rewrite it as clean board text: correct spelling and grammar, drop filler and repeats, spell out shorthand ("fx" → "for example"; keep command, tool and product names), split run-on thoughts into the pattern's lines, and turn questions into what is to be found out ("Find out why /send fails from the app"). Keep every point and its meaning; add none.
- Fill a line only from what the ticket text (with Quinn's answers from step 3a) says; drop the lines it gives nothing for, and list each dropped line as a loose end. Effort, priority, offer item and benefit values come from Quinn, verbatim.
- Dependencies line: the ids the text names, checked to exist on the board; text names none → drop the line.
- Tags: `#bug` only when the ticket is mainly a defect to fix, `#urgent` when it says urgent, `hotfix` in the title when it says hotfix. `/work` cuts a `bugfix/` or `hotfix/` branch from `#bug` and `hotfix`, so a feature that also fixes something gets neither. Only tags the board already uses, plus `#bug`.
- Lines start with one tab.

**Done when:** every point of the ticket text is on the card in clean wording, every line traces to the text, and every pattern line without a source is a loose end.

## 5. Write

Read the board file again right before the edit: Quinn edits it in Obsidian at any time. Insert the card block at the end of `## To do` (case-insensitive): after that column's last card, before the blank lines that end the column. Change nothing else. No `To do` column → stop: "no To do column on <board file>".

Print the card block and the loose ends.

**Done when:** the board file has the new card as the last card in `To do`, every other line unchanged, and the card and loose ends are printed.

## 6. Tick the to-do (`todo:` only)

After the card is written, tick the matching to-do:

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/../briefing/gather.sh --done-text "<to-do text>"
```

An `error:` line → show it; the card stays.

**Done when:** the to-do line in `Briefing notes.md` is ticked, or the error is shown.
