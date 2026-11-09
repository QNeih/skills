# Vault board

The board is the lookup's `board-file:`, an Obsidian Kanban file. Each `## <name>` heading is a column; column names match case-insensitively (`In Progress` is `In progress`). A **card block** is a `- [ ]` or `- [x]` line starting with `**<KEY>-<n> · <title>**`, plus the tab-indented lines under it. The ticket id and ref are both `<KEY>-<n>`.

Quinn edits the board in Obsidian at any time: Read it again right before every edit, and change only the card block you work on.

## Pick

Rank the cards in `To do`: those tagged `#urgent` first, then board order. The list is one `<KEY>-<n> · <title>` line per card, in that order.

`To do` empty or missing → print the cards in `In progress` and ask which one; wait for the answer.

## Find

The card whose first line contains `**<id> ·`. Not found → stop: "<id> is not on <board file>".

## Claim

- Card in `In progress` → leave it.
- Card in `Done` → stop and ask whether to reopen it.
- No `In progress` column → leave the card; loose end "no In progress column on <board file>".
- Else → move the card block, unchanged, to the end of `In progress`: after that column's last card, before the blank lines that end the column.

No assignee, no fix version.

## Branch

- Name: card text contains `hotfix` (any case) → `hotfix/<id>`; card has the `#bug` tag → `bugfix/<id>`; else `feature/<id>`.
- Base: `develop` if it exists locally or on `origin`, else `main`.
- Once the branch is cut, append the tab-indented line ``Branch `<branch>` `` as the card block's last line (skip if the card already has it).

## Import

- Title: the card title. `ref:` the id. `board:` the board file path.
- `Type:` bug, hotfix or feature, as for the branch name; no priority or tracker status line.
- `## Description`: the card's indented lines, verbatim, without the leading tab.
- No `## Attachments` and no `## Comments` sections.
