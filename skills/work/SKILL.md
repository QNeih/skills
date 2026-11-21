---
name: work
description: Start a ticket from the project's board — claim it, cut its branch, import it to .scratch, then start the route that works on it.
argument-hint: "[KEY-12 | 12], or nothing for the top unblocked ticket"
---

# Work

`/work [KEY-12|12]` starts one ticket: claim it on the project's board, cut its branch, import it to `ticket.md`, write the handoff, then print the route and start it. `/send` ships the work later.

The steps are the same on every board. What a board does at a step lives in its **board file**, read once in step 1:

| Board | Board file |
| --- | --- |
| GitHub Project (`board: github`) | `${CLAUDE_SKILL_DIR}/GITHUB.md` |
| Jira (`board: jira`, or a link on an Atlassian site) | `${CLAUDE_SKILL_DIR}/JIRA.md` |
| Any other link or text, e.g. Azure DevOps | `${CLAUDE_SKILL_DIR}/OTHER.md` |

## 1. Project and board

Run from the project folder (a worktree works too):

```bash
bash ${CLAUDE_SKILL_DIR}/project.sh
```

- Follow `${CLAUDE_SKILL_DIR}/BOARD.md` to get the board (no board yet → it asks the board question), then read the board's file.
- `<dir>` is the `dir:` line: the main checkout, or the project folder without git. **Git** means `git -C <dir> rev-parse` succeeds; without git, skip every git step and write no branch anywhere.

**Done when:** project, `<dir>`, board and git-or-not are known, and the board file is read.

## 2. Pick the ticket

- `$ARGUMENTS` matches `[A-Z][A-Z0-9]+-[0-9]+` → that id.
- Digits, with or without `#` → on a number-only tracker (`OTHER.md` › Ids) the digits are the id; else `<key>-<digits>`, `<key>` from the lookup's `key:`. No key → on GitHub the digits are the id; elsewhere stop and ask for the full id.
- A number-only tracker's ref (`AB#1234`) → its number is the id. A GitHub ref (`owner/repo#12`) → its number, read as digits above.
- Empty → the board file's **Pick**: print the ranked list of unblocked tickets to Quinn, then take its top ticket.
- Anything else → stop and ask for a ticket.

Then the board file's **Find**.

**Done when:** one ticket id and its ref, found on the board; with no argument, the ranked list is printed.

## 3. Claim

The board file's **Claim**.

**Done when:** the ticket is in progress on the board, or a stop says why not, or it is reported as could not fix, with its cause.

## 4. Branch (git only)

Each ticket works in its own **ticket worktree** `<wt>` = `<dir>/.claude/worktrees/<id>`, the folder the dashboard's `claude --bg -w <id>` also uses, so tickets can run in parallel. The main checkout's branch is never changed.

1. Branch name and `<base>` from the board file's **Branch**. `origin` exists → `git -C <dir> fetch origin` (`cannot open '.git/FETCH_HEAD'` → rerun unsandboxed). `<start point>`: `origin/<base>` when it exists, else `<base>`; neither → stop and ask.
2. Where this session works (`git rev-parse --show-toplevel`):
   - `<wt>` → stay.
   - Another ticket's worktree (`<dir>/.claude/worktrees/<other id>`) → stop: ask Quinn to start this ticket in its own session.
   - Any other linked worktree (`git rev-parse --git-dir` differs from `--git-common-dir`) → stay: it is this session's own.
   - The main checkout → `<wt>` missing: `git -C <dir> worktree add <wt> -b <branch> <start point>` (branch exists → `git -C <dir> worktree add <wt> <branch>`, and say so). Then `cd <wt>`. From here on the ticket's code work happens in `<wt>`: commands as `cd <wt> && …` or `git -C <wt> …`, file edits by absolute path under `<wt>`. `<dir>` stays the main checkout; the **ticket files** go in `<wt>` (steps 5 and 7). No EnterWorktree: it would make the main checkout read-only for this session.
3. `git status --porcelain --untracked-files=no` prints anything → stop and ask: stash, commit, or discard.
4. `git branch --show-current` is not `<branch>` (a worktree the dashboard made is on `worktree-<id>`) → `git checkout -b <branch> <start point>`; branch exists → `git checkout <branch>` and say so. The branch it left is `worktree-<id>` → delete it: `git rev-list -1 worktree-<id> --not <branch> --remotes` prints nothing (no commit of its own) → `git branch -D worktree-<id>`; prints a commit → keep it and report it as could not fix, with its cause.
5. With an origin → `git push -u origin HEAD`.
6. Note the branch on the board, as the board file's **Branch** says.

**Done when:** this session works in `<wt>` (or the linked worktree it started in), `git branch --show-current` prints the branch (tracking `origin` when there is one), the main checkout's branch is unchanged, no `worktree-<id>` branch is left (or it is reported as could not fix), and the board shows the branch if the board file notes branches.

## 5. Import

The ticket files live in `<root>`: with git the worktree this session works in after step 4, `git rev-parse --show-toplevel` (`<wt>`, or the linked worktree it started in), so any session can write them there; without git `<dir>`.

Folder: `<root>/.scratch/<id>-<slug>/`, `<slug>` a 2–4 word kebab-case English gist of the title. A folder starting with `<id>-` exists → reuse it.

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

Write `<root>/.handoffs/HANDOFF-<id>.md`. Pointers only, every path absolute:

- id, title, board (file path or link)
- branch, base and ticket worktree path, or "no git"
- the `ticket.md` path
- route and why
- what each step could not fix, and why

**Done when:** the handoff exists and every line is a pointer, or names what a step could not fix, and why.

## 8. Start the route

Print what the steps could not fix, and why, then this line:

```
Route: /<skill> — <one-line reason>
```

Then start the route in this session, with the `ticket.md` path as its input. With git, all of the route's code work happens in the worktree from step 4, by path as step 4 says:

- `/implement` → right away, hand the coding to one sub-agent: Agent tool, model `fable`, effort `low`. The call fails on Fable's usage limit → the same call with model `opus`, effort `medium`.
  - Its brief, every path absolute: read `~/.claude/skills/implement/SKILL.md` and do its implementing, testing and commit, since the review runs in this session afterwards; input the `ticket.md` path; work in the worktree from step 4; report what changed, the test results and what it could not fix, and why.
  - When it reports, send the review's findings worth fixing to that sub-agent with SendMessage.
- `/diagnosing-bugs`, `/grill-with-docs`, `/wayfinder` → read `~/.claude/skills/<name>/SKILL.md` and follow it, opening with a question to Quinn.
- `/wayfinder` adds, while this session orchestrates its map:
  - When the current ticket's file shows `status: closed`, start the next frontier ticket in a new session without asking (with git: `claude --bg -w <its id>` from `<dir>`, so it works in that ticket's own worktree), and post one line naming it and why so Quinn can stop it. A report that only says "waiting on user" is not a close.
  - One ticket session at a time; research tickets go to background subagents alongside.
  - Archive the closed ticket's session right away: an idle unarchived session shows as waiting on Quinn.
  - Still ask before writing tickets for "Not yet specified" items and before starting `/to-spec`.
  - Each brief tells the child to read `~/.claude/skills/wayfinder/SKILL.md` by path; it may not be in the child's skill list.
- `/implement` and `/diagnosing-bugs` end, once the code is committed, with the Skill tool `code-review` in this session: fixed point `origin/<base>`, spec the `ticket.md` path. No code reaches `/send` unreviewed.
- `/grill-with-docs` ends, once Quinn confirms the shared understanding and the ticket needs code, by writing the decisions into `ticket.md`'s `## Decisions` section (one line each: what, why, and the rejected option; `/send` copies them into the brain), setting `Status: ready-for-agent` and `Next: /implement`, then starting `/implement` as above: the sub-agent knows only `ticket.md`, so every decision is in it first.
- `/build` → the Skill tool `build`.
- `needs-info` → print the questions for the reporter and stop.

**Done when:** the route line is printed and the route has started, or `needs-info` stopped with its questions.
