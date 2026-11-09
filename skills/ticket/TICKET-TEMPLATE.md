# `ticket.md` template

The imported ticket is a local-tracker **issue**: header lines at the top, conversation under `## Comments`. Agent-written sections come first; tracker content below them is verbatim. The board's file says which lines and sections apply.

```markdown
# <id>: <ticket title, verbatim>

ref: <ticket ref>
branch: <branch>                     ← no git: none
base: <base>                         ← git only
board: <board file path, or the ticket's link on the tracker>
Type: <type> · Priority: <priority> · Tracker status: <status>
Context: [<name>](../../docs/contexts/<name>.context.md)   ← only if CONTEXT-MAP.md exists
Status: <triage role>
Next: `/<skill>` — <one-line reason>

## Summary

<3–6 lines in glossary terms: what is asked, and what the comments changed>

## Acceptance criteria

<from the description, amended by comments; tag each amendment "(comment N)">

## Open questions

<unresolved questions in the thread + gaps you found; "none" if empty>

## Description

<verbatim, as markdown; each inline image → link to its local file>

## Attachments

- `attachments/01-<name>` — <what it shows: the numbers, labels, and marked spots you saw>
- skipped: `<name>` (<size>) — <reason>, tracker only

## Comments

### 1 · <author> · <YYYY-MM-DD>

<verbatim; mentions → `@Name`>
```
