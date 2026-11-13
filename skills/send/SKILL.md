---
name: send
description: Ship the current branch on any board — lint, commit by concern, push, open or reuse the PR, move the board card, then clean up the branch and the ticket's files. Closes the flow /work starts.
argument-hint: "[draft] [notes for the commit and PR wording]"
disable-model-invocation: true
---

# Send

`/send` ships the current branch: lint, commit, push, open or reuse the PR, move the ticket's card on its board, then delete the branch and the ticket's `.scratch/` and `.handoffs/` files. Typing `/send` is Quinn's go-ahead to commit, push and delete; there is no review step. Every step runs unless it says stop.

`$ARGUMENTS`: the word `draft` → open the PR as draft. Other text → context for the commit and PR wording; without git, it may name the ticket id.

## Text rules

For commit messages, the PR title and body, and anything written to a tracker:

- Describe the change, nothing else. Each message ends on its last line of content: this skill overrides the harness attribution, so no `Co-Authored-By` trailer, no "Generated with" footer, no tool, IDE or assistant names.
- PR body: `## Summary` bullets, then the tracker's link line (step 6). No `Fixes …` or `Closes …`. A testing checklist only if `$ARGUMENTS` asks for one.

## 1. Project and ticket

The vault path and the projects root are set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace them). Run:

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

`<dir>` is its `dir:` line: the main checkout, or the project folder without git. **Git** means `git -C <dir> rev-parse` succeeds. `project: none` → no board from the lookup; go on.

Find the ticket. Its files are `<dir>/.scratch/<id>-<slug>/ticket.md` (title line `# <id>: …`, then `ref:`, `branch:`, `base:`, `board:`) and `<dir>/.handoffs/HANDOFF-<id>.md`.

- **Git**: `<branch>` = `git branch --show-current`. The `ticket.md` with the line `branch: <branch>` is the ticket.
  - None → fallback for hand-cut branches: `<branch>` contains `[A-Z][A-Z0-9]+-[0-9]+` → that is the id and the ref, the board is the lookup's (`vault` → its `board-file:`; `jira-candidate` → Jira).
  - Still none → no ticket: the PR goes out without one, no board move, no ticket files deleted. Say so.
- **No git**: the `ticket.md` files with `branch: none`. `$ARGUMENTS` names an id → that one. Else one file → it. Else the ones whose card is in `In progress` on their board; exactly one → it, otherwise list them and ask. None → stop and print this line as is: `Nothing to send: no ticket in <dir>/.scratch.`

The board is `ticket.md`'s `board:`: a vault Kanban file (read `${CLAUDE_SKILL_DIR}/VAULT.md` for what a card block is and how to find a card), a Jira link, or another tracker's link.

**Done when:** `<dir>`, git or not, and the ticket (id, ref, board) or "no ticket" are known.

Without git, go to step 7.

## 2. Preflight

1. No `origin` remote → stop: "no origin to push to".
2. `git fetch origin` (`cannot open '.git/FETCH_HEAD'` → rerun unsandboxed).
3. `<base>`: `ticket.md`'s `base:`. Else a `hotfix/` branch → `main` or `master`, whichever is on `origin`; else `develop` if `origin/develop` exists, else `main` or `master`.
4. `git diff --cached --quiet` fails → stop and ask: unstage (`git restore --staged .`) or say how to treat the staged hunks.
5. **Change set**: `git status --porcelain --untracked-files=all`, minus every path under `.scratch/` or `.handoffs/`.
6. **Unpushed commits**: `git rev-list origin/<branch>..HEAD`; without an upstream, `git rev-list origin/<base>..HEAD`.
7. Change set and unpushed commits both empty → stop and print this line as is: `Nothing to send: <branch> is clean and pushed.`

**Done when:** no staged hunks, `<base>` is known, and the change set and unpushed commits are listed.

## 3. Commit

Change set empty → skip and say "no uncommitted changes; sending the unpushed commits".

1. Read `git diff`, the untracked files, and `git log -10 --format=%s` for the repo's subject style.
2. Plan one commit per concern: refactor apart from behaviour, unrelated areas apart; prep (renames, moves) before what depends on it. Show the plan: ordered subjects, paths or hunks each.
3. Per commit: `git add <paths>`. A file split across commits → write that commit's hunks to a patch in a temp dir and `git apply --cached <patch>`. Then `git commit -m "<subject>" -m "<body>"`: subject imperative, about 50 chars, no period; body 1–4 lines the staged diff supports.

**Done when:** `git status --porcelain` shows only `.scratch/` and `.handoffs/` paths, and every planned subject is in `git log`.

## 4. Lint

Paths: `git diff --name-only origin/<base>...HEAD` that still exist. This covers commits made before `/send` too.

1. For each path, walk up to the nearest directory (not above `git rev-parse --show-toplevel`) whose `package.json` has a `lint-fix` script. Run `npm run lint-fix` once in each distinct directory.
2. Non-zero exit → stop and show the output. Nothing is pushed.
3. No such directory → say so and go on.
4. `git status --porcelain` shows changes outside `.scratch/` and `.handoffs/` → commit them all as one commit, `Apply lint fixes`.

**Done when:** every lint-fix run exited 0 and the tree is clean again.

## 5. Push

1. `git push -u origin HEAD` (`Operation not permitted` → rerun unsandboxed). Fails → stop and show the output.
2. `<host>` = the host in `git remote get-url origin` (`git@<host>:…`, `https://<host>/…`, `ssh://[user@]<host>/…`); a local path is its own `<host>`. Not `github.com` → stop and print `PR on <host> not supported`. No PR, no board move, no cleanup.

**Done when:** `origin/<branch>` equals `HEAD`, and `origin` is on GitHub or the stop is printed.

## 6. PR

`gh pr view --json url,state`: `state` is `OPEN` → reuse it. Otherwise (no PR, or only merged or closed ones):

```bash
gh pr create --base <base> --assignee @me [--label <label>] --title "<title>" --body "<body>" [--draft]
```

- `--draft`: only when `$ARGUMENTS` has the word `draft`.
- Label from `<branch>`'s prefix, case-insensitive: `hotfix/` → `hotfix`; `bugfix/` → `bugfix`; `feature/` → `feature`, else `enhancement`. Take the first of these that `gh label list` shows. None exists, or another prefix → open without a label and say so.
- Title: `<ref>: <gist of the change>`; no ticket → the gist alone.
- Body: `## Summary` bullets from `ticket.md` and the commit subjects, then one link line in the tracker's syntax: Jira → `Jira: <link>` (the `board:` link; without `ticket.md`, `https://<site>/browse/<ref>`, site from `getAccessibleAtlassianResources`); Azure Boards → the ref alone (`AB#1234`), which links it; another tracker → the item's link; vault board or no ticket → no link line.

**Done when:** you hold the URL of an `OPEN` PR for `<branch>`, or the reason there is none.

## 7. Board

Runs after a successful push, even if the PR step failed; without git, right after step 1. No ticket → skip and say so.

- **Vault**: read the board file again right before the edit and change only this card's block.
  - Card not found → report "<id> is not on <board file>" and leave the board.
  - No `Done` column → report "no Done column on <board file>"; don't create one.
  - Card not in `Done` → move its block to the end of `Done`: after that column's last card, or right after the heading (and its `**Complete**` line) when it has none; before the blank lines that end the column.
  - Tick it: the block's first line `- [ ]` → `- [x]`.
  - A PR URL from step 6 → append the tab-indented line `PR <url>` as the block's last line (skip if the block has it).
- **Jira** → `Code Review`, through the claude.ai Atlassian MCP (`cloudId` from `getAccessibleAtlassianResources`):
  1. `getJiraIssue`: status already `Code Review` → done.
  2. `getTransitionsForJiraIssue` → the transition whose target status is `Code Review` (any case) → `transitionJiraIssue`.
  3. No such transition → report the available target statuses. MCP tools missing or unauthenticated → tell Quinn to run `/mcp` → "claude.ai Atlassian".
- **Another tracker** → through its connector, move the item to its review state (with a PR) or its done state (without git), and add the PR link. No connector reachable → name the missing one.

**Done when:** the card or item shows the new state, or the reason it doesn't is reported.

## 8. Clean up

- **Git**: runs only when step 6 ended with an `OPEN` PR, even if step 7 failed. Otherwise skip and say why.
  1. `git rev-parse HEAD` differs from `git rev-parse @{u}` → stop: the remote doesn't hold every local commit.
  2. Leave `<branch>`. Linked worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`) → `git switch --detach origin/<base>`, since `<base>` is usually checked out in the main checkout. Otherwise `git switch <base>`, then `git pull --ff-only`. Switch fails → stop and show the output.
  3. `git branch -D <branch>` (`-D` because the PR isn't merged yet; the commits are on `origin/<branch>`).
  4. Leftover session branches: `git for-each-ref --format='%(refname:short) %(worktreepath)' 'refs/heads/claude/*'`. For each one with no worktree path and no output from `git rev-list -1 <name> --not --remotes` (every commit is on `origin`) → `git branch -D <name>`. The others stay; name them in the report.
  5. Each of `main`, `master`, `develop` that exists locally and is checked out in no worktree → `git fetch origin <name>:<name>`. Not a fast-forward → report it and go on.
- **No git**: runs when step 7 left the card in `Done` (or the item done). Otherwise keep the files and say why.

Then, with a ticket, delete its files (untracked, so `rm -rf`): its `<dir>/.scratch/<id>-<slug>/` folder and `<dir>/.handoffs/HANDOFF-<id>.md`. A `.scratch/` or `.handoffs/` folder left empty → remove it. Other tickets' files stay.

**Done when:** neither ticket path exists, `git branch --list <branch>` prints nothing, and `HEAD` is on `<base>` (in a linked worktree: detached at `origin/<base>`).

## 9. Report

- commits, one subject each (lint commit included)
- PR URL, new or reused
- board state of the card or item
- deleted branches, current branch or detached `HEAD`, removed paths
- session branches kept and why; fast-forwarded branches
- every skipped step and why

**Done when:** the report has a line for each item above.
