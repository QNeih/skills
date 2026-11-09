---
name: ticket
description: Start a ticket from the project's board — claim it, cut its branch, import it to .scratch, then start the route that works on it.
argument-hint: "[KEY-12 | 12], or nothing for the top unblocked ticket"
disable-model-invocation: true
---

# Ticket

`/ticket [KEY-12|12]` starts one ticket: claim it on the project's board, cut its branch, import it to `ticket.md`, write the handoff, then print the route and start it. `/send` ships the work later.

The steps are the same on every board. What a board does at a step lives in its **board file**, read once in step 1:

| Board | Board file |
| --- | --- |
| Vault Kanban file (`board: vault`) | `${CLAUDE_SKILL_DIR}/VAULT.md` |
| Jira (`board: jira-candidate`, or a link on an Atlassian site) | `${CLAUDE_SKILL_DIR}/JIRA.md` |
| Any other link or text, e.g. Azure DevOps | `${CLAUDE_SKILL_DIR}/OTHER.md` |

## 1. Project and board

The vault path and the projects root are set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace them). Run:

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

- `project: none` → stop and print its `reason:`.
- Then follow `${CLAUDE_SKILL_DIR}/BOARD.md` to get the board (on a Jira candidate it checks the key first), and read its board file.
- `<dir>` is the `dir:` line: the main checkout, or the project folder without git. **Git** means `git -C <dir> rev-parse` succeeds; without git, skip every git step and write no branch anywhere.

**Done when:** project, `<dir>`, board and git-or-not are known, and the board file is read.

## 2. Pick the ticket

- `$ARGUMENTS` matches `[A-Z][A-Z0-9]+-[0-9]+` → that id.
- Digits only → on a number-only tracker (`OTHER.md` › Ids) the digits are the id; else `<key>-<digits>`, `<key>` from the board file (vault: the lookup's `key:`). No key → stop and ask for the full id.
- A number-only tracker's ref (`AB#1234`) → its number is the id.
- Empty → the board file's **Pick**: print the ranked list of unblocked tickets to Quinn, then take its top ticket.
- Anything else → stop and ask for a ticket.

Then the board file's **Find**.

**Done when:** one ticket id and its ref, found on the board; with no argument, the ranked list is printed.

## 3. Claim

The board file's **Claim**.

**Done when:** the ticket is in progress on the board, or a stop or loose end says why not.

## 4. Branch (git only)

1. `git status --porcelain --untracked-files=no` prints anything → stop and ask: stash, commit, or discard.
2. Branch name and `<base>` from the board file's **Branch**.
3. `origin` exists → `git fetch origin` (`cannot open '.git/FETCH_HEAD'` → rerun unsandboxed). Cut from `origin/<base>` when it exists, else from `<base>`:
   ```bash
   git checkout -b <branch> <start point>
   git push -u origin HEAD   # only with an origin
   ```
   Branch exists → check it out and say so. Base missing → stop and ask.
4. Note the branch on the board, as the board file's **Branch** says.

**Done when:** `git branch --show-current` prints the branch (tracking `origin` when there is one), and the board shows it if the board file notes branches.

## 5. Import

Folder: `<dir>/.scratch/<id>-<slug>/`, `<slug>` a 2–4 word kebab-case English gist of the title. A folder starting with `<id>-` exists → reuse it.

Write `ticket.md` there from `${CLAUDE_SKILL_DIR}/TICKET-TEMPLATE.md`, filled as the board file's **Import** says. `<dir>/CONTEXT-MAP.md` exists → name the contexts the ticket touches and write the agent sections in their glossary terms. Leave `Status:` and `Next:` for step 6.

**Done when:** `ticket.md` has the title, `ref:`, `branch:`, `board:` and the ticket's full text, with every comment and attachment the board file's **Import** asks for.

## 6. Route

Take the first row that fits and write its status and route into `ticket.md`'s `Status:` and `Next:`.

| Ticket shape | Status | Route |
| --- | --- | --- |
| Only the reporter can answer (missing acceptance criteria, comments disagree) | `needs-info` | none: list the questions for the reporter |
| Bug, cause not obvious | `ready-for-agent` | `/diagnosing-bugs` |
| Concrete acceptance criteria, one area, one session | `ready-for-agent` | `/implement` |
| One session, open design questions | `needs-triage` | `/grill-with-docs` |
| Multi-session build | `needs-triage` | `/build` |
| Too big or foggy to see the way | `needs-triage` | `/wayfinder` |

No row fits → `needs-triage`, `/grill-with-docs`.

**Done when:** `ticket.md` has both lines filled.

## 7. Handoff

Write `<dir>/.handoffs/HANDOFF-<id>.md`. Pointers only, every path absolute:

- id, title, board (file path or link)
- branch and base, or "no git"
- the `ticket.md` path
- route and why
- loose ends from every step

**Done when:** the handoff exists and every line is a pointer or a loose end.

## 8. Start the route

Print the loose ends, then this line:

```
Route: /<skill> — <one-line reason>
```

Then start the route in this session, with the `ticket.md` path as its input:

- `/implement` → read `~/.claude/skills/implement/SKILL.md` and follow it. Start coding right away.
- `/diagnosing-bugs`, `/grill-with-docs`, `/wayfinder` → read `~/.claude/skills/<name>/SKILL.md` and follow it, opening with a question to Quinn.
- `/diagnosing-bugs` ends, once the fix is in, with the Skill tool `code-review`: fixed point `origin/<base>`, spec the `ticket.md` path.
- `/build` → the Skill tool `build`.
- `needs-info` → print the questions for the reporter and stop.

**Done when:** the route line is printed and the route has started, or `needs-info` stopped with its questions.
