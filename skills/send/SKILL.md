---
name: send
description: Ship the current branch on any board — commit by concern, rebase, lint, test, push, open or reuse the PR, move the board card, then clean up the branch, the ticket worktree and the ticket's files. A ticket branch with nothing on it is closed instead: card to Done with the reason, same cleanup. Closes the flow /work starts.
argument-hint: "[draft] [notes for the commit and PR wording, or the close reason]"
---

# Send

`/send` ships the current branch: commit, rebase onto the base branch, lint, test, push, open or reuse the PR, move the ticket's card on its board, then stop the ticket's dev servers and delete the branch, the ticket worktree and the ticket's `.scratch/` and `.handoffs/` files. A ticket whose branch has nothing on it is **closed** instead: no commit, push or PR, the card moves to Done with the reason, and the same cleanup runs. Typing `/send` is Quinn's go-ahead to commit, push and delete; there is no review step. Every step runs unless it says stop.

`$ARGUMENTS`: the word `draft` → open the PR as draft. Other text → context for the commit and PR wording, or the reason on a close; without git, it may name the ticket id.

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

- **Git**: a session started in the main checkout that works on its ticket in the ticket worktree `/work` made (`<dir>/.claude/worktrees/<id>`) → `cd` there first; steps 1–8 run in it. `<branch>` = `git branch --show-current`. The `ticket.md` with the line `branch: <branch>` is the ticket.
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
5. **Port change**: `git diff -- .claude/launch.json` prints a diff, and every changed line differs from the line it replaces only in a number → `git restore .claude/launch.json`. That is a dev server's port moved for this session: it is never committed, and left in place it blocks the worktree's removal in step 8. The diff changes anything else → stop and ask which lines to commit.
6. **Change set**: `git status --porcelain --untracked-files=all`, minus every path under `.scratch/` or `.handoffs/`.
7. **Branch commits**: `git rev-list origin/<base>..HEAD`, pushed or not. Commits already on `origin` still need their PR, board move and cleanup.
8. Change set and branch commits both empty:
   - No ticket → stop and print this line as is: `Nothing to send: <branch> has no changes against <base>.`
   - A ticket → this is a **close**. Reason: `$ARGUMENTS` without the word `draft`; empty → ask Quinn for one line and wait, changing nothing before the answer. Skip steps 3–6 and go to step 7 (Board).

**Done when:** no staged hunks, `<base>` is known, and the change set and branch commits are listed, or a close has its reason.

## 3. Commit

Change set empty → skip and say "no uncommitted changes; sending the branch commits".

1. Read `git diff`, the untracked files, and `git log -10 --format=%s` for the repo's subject style.
2. Plan one commit per concern: refactor apart from behaviour, unrelated areas apart; prep (renames, moves) before what depends on it. Show the plan: ordered subjects, paths or hunks each.
3. Per commit: `git add <paths>`. A file split across commits → write that commit's hunks to a patch in a temp dir and `git apply --cached <patch>`. Then `git commit -m "<subject>" -m "<body>"`: subject imperative, about 50 chars, no period; body 1–4 lines the staged diff supports.

**Done when:** `git status --porcelain` shows only `.scratch/` and `.handoffs/` paths, and every planned subject is in `git log`.

## 4. Rebase, lint and test

In this order. A stop in any of them means nothing is pushed.

**Rebase**: `git rebase origin/<base>`, so the PR can't conflict with what merged since the branch was cut.

- Conflict → resolve it with the Skill tool `resolving-merge-conflicts`. A hunk that `ticket.md` and both sides leave undecided → `git rebase --abort`, stop and name the conflicting files.
- It fails for another reason → stop and show the output.
- `git rev-list origin/<base>..HEAD` prints nothing afterwards (`<base>` already holds every change) → the branch has nothing on it: apply step 2's rule for an empty change set with no branch commits.

**Lint**

Paths: `git diff --name-only origin/<base>...HEAD` that still exist. This covers commits made before `/send` too.

1. For each path, walk up to the nearest directory (not above `git rev-parse --show-toplevel`) whose `package.json` has a `lint-fix` script. Run `npm run lint-fix` once in each distinct directory.
2. Non-zero exit → stop and show the output. Nothing is pushed.
3. No such directory → say so and go on.
4. `git status --porcelain` shows changes outside `.scratch/` and `.handoffs/` → commit them all as one commit, `Apply lint fixes`.

**Test**: at `git rev-parse --show-toplevel`, the first of `test.sh` and `tests/run.sh` that exists → `bash <script>` from there. Non-zero exit → stop and show the output. Neither exists → say "no test.sh or tests/run.sh: tests not run" and go on.

**Done when:** `git merge-base --is-ancestor origin/<base> HEAD` succeeds, every lint-fix run and the test script exited 0 (or the project has no test script), and the tree is clean again.

## 5. Push

1. `git push --force-with-lease -u origin HEAD` (`Operation not permitted` → rerun unsandboxed). The lease is there because the rebase may have rewritten commits that `/work` already pushed. Fails → stop and show the output.
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

**Merge on send**: a `CLAUDE.md` rule says to merge this repo's PRs on send, and the PR isn't a draft → `gh pr merge <url> --squash --delete-branch`. It fails → stop and show the output; the board move and cleanup don't run.

**Conflicting PRs**: `gh pr list --state open --limit 100 --json number,title,headRefName,mergeable`. Every PR whose `headRefName` is not `<branch>` and whose `mergeable` is `CONFLICTING` goes into the report with its number, title and branch. `UNKNOWN` (GitHub works it out only once asked, so this is usual right after a merge) → run the list again right before the report (step 9); still `UNKNOWN` → report that PR as not yet checked. Their branches stay as they are: each one is rebased by `/send` in its own ticket's session.

**Done when:** you hold the URL of an `OPEN` PR for `<branch>` (or, merged on send, a `MERGED` one), or the reason there is none; and every other open PR is noted as conflicting or `UNKNOWN`, or left out as mergeable.

## 7. Board

Runs after a successful push, even if the PR step failed; on a close, right after step 2; without git, right after step 1. No ticket → skip and say so.

- **Vault**: read the board file again right before the edit and change only this card's block.
  - Card not found → report "<id> is not on <board file>" and leave the board.
  - No `Done` column → report "no Done column on <board file>"; don't create one.
  - Card not in `Done` → move its block to the end of `Done`: after that column's last card, or right after the heading (and its `**Complete**` line) when it has none; before the blank lines that end the column.
  - Tick it: the block's first line `- [ ]` → `- [x]`.
  - A PR URL from step 6 → append the tab-indented line `PR <url>` as the block's last line (skip if the block has it).
  - Close → append the tab-indented line `Closed without code: <reason>` as the block's last line instead.
- **Jira** → `Code Review`, through the claude.ai Atlassian MCP (`cloudId` from `getAccessibleAtlassianResources`):
  1. `getJiraIssue`: status already `Code Review` → done.
  2. `getTransitionsForJiraIssue` → the transition whose target status is `Code Review` (any case) → `transitionJiraIssue`.
  3. No such transition → report the available target statuses. MCP tools missing or unauthenticated → tell Quinn to run `/mcp` → "claude.ai Atlassian".
- **Another tracker** → through its connector, move the item to its review state (with a PR) or its done state (without git), and add the PR link. No connector reachable → name the missing one.
- **Close on Jira or another tracker** (instead of the Jira and Another tracker bullets): the state comes from `close:` in the frontmatter of the lookup's `note:`.
  - No `close:` line → ask Quinn once: "Which state does closing a ticket without code move it to in <project>? Name the state, or `leave`." Save the answer as `close: "<answer>"` in the note's frontmatter, after `board:` if it has one, else before the closing `---`. No note (`project: none`) → ask, don't save.
  - `leave` → don't move the item; report "close <ref> on the tracker yourself" with its link.
  - Else move the item to that state (Jira: the transition whose target status matches, any case) and add the comment `Closed without code: <reason>`. No such transition → report the available target statuses and change nothing.

**Done when:** the card or item shows the new state, or the reason it doesn't is reported.

## 8. Clean up

- **Git**: runs when step 6 ended with an `OPEN` PR or one it merged, even if step 7 failed; on a close, only when step 7 moved the card or item (or Quinn answered `leave`), since nothing else records the ticket. Otherwise skip and say why.
  1. `git rev-parse HEAD` differs from `git rev-parse @{u}` → stop: the remote doesn't hold every local commit. Merged on send → skip this check (`--delete-branch` removed the upstream); `git fetch origin` instead, so `origin/<base>` has the merge. Close → skip this check.
  2. Leave `<branch>`. Linked worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`) → `git switch --detach origin/<base>`, since `<base>` is usually checked out in the main checkout. Otherwise `git switch <base>`, then `git pull --ff-only`. Switch fails → stop and show the output.
  3. `git branch -D <branch>` (`-D` because the PR may not be merged yet; its commits are on `origin/<branch>`). Close and `origin/<branch>` exists → also `git push origin --delete <branch>`.
  4. Leftover session branches: `git for-each-ref --format='%(refname:short) %(worktreepath)' 'refs/heads/claude/*' 'refs/heads/worktree-*'`. For each one with no worktree path and no output from `git rev-list -1 <name> --not --remotes` (every commit is on `origin`) → `git branch -D <name>`. The others stay; name them in the report.
  5. Each of `main`, `master`, `develop` that exists locally and is checked out in no worktree → `git fetch origin <name>:<name>`. Not a fast-forward → report it and go on.
  6. Dev servers, with a ticket: the ticket worktree `<dir>/.claude/worktrees/<id>` exists → `bash ${CLAUDE_SKILL_DIR}/stop-servers.sh <dir>/.claude/worktrees/<id>`. It stops every process that listens on a TCP port from inside that folder and prints one `stopped:` line each. An `error:` line → show it and stop. No ticket worktree (the ticket was worked in the main checkout) → stop nothing and say so: a server listening there may be one Quinn runs.
- **No git**: runs when step 7 left the card in `Done` (or the item done). Otherwise keep the files and say why.

Then, with a ticket, capture loose ends (below), then delete its files (untracked, so `rm -rf`): its `<dir>/.scratch/<id>-<slug>/` folder and `<dir>/.handoffs/HANDOFF-<id>.md`. A `.scratch/` or `.handoffs/` folder left empty → remove it. Other tickets' files stay.

Last, with git and a ticket: the ticket worktree `<wt>` = `<dir>/.claude/worktrees/<id>`. It doesn't exist → skip. Else run `claude agents --json --all --cwd <dir>`:

- It lists a session with `kind` `background` and `cwd` `<wt>` (this session, when it was started with `claude --bg -w <id>`) → leave `<wt>`: a session cannot remove the folder it runs in, so the worktree goes with the session. `git status --porcelain` in `<wt>` prints anything → name those files in the report: `claude rm` refuses a worktree with uncommitted changes. Report the line `claude rm <session id>`, the listed session's `id`; Quinn removes the session (dashboard: `a a`), and that deletes the worktree.
- No such session → `cd <dir> && git worktree remove <wt>`, without `--force`. Git refuses (untracked or modified files) → stop and name the files from its output. Every later command runs from `<dir>`.

**Loose ends**: at most one per ticket becomes a to-do (see `GLOSSARY.md`). Collect them from the handoff and from your own session's reports; those that share a cause count as one. A loose end qualifies only if all hold:

- still open after the merge or close (fixed or settled points drop),
- **breaking** or **ticket-worthy**. Breaking: something fails or is lost now (a build, a test, data, a step that was skipped). Ticket-worthy: Quinn would open a ticket for it unprompted. Checks, one-off chores (restart a server, remove a worktree), test-coverage gaps, wording and style, and decisions with nothing breaking are neither. In doubt → neither,
- no open to-do names its cause: read all `- [ ]` lines of `<vault>/Briefing notes.md`, whatever their project tag,
- vault board only: no open card (any column but Done) covers it. On Jira and other trackers skip this check: no search, no marker,
- written as standalone ticket text: what, where, why, and the ticket it came from. `/ticket` plus a grilling must be able to turn it into a card that overlaps no other.

Keep the most important one that qualifies, a breaking one before a ticket-worthy one. Append it with `VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/../note/note.sh` (text on stdin, run from `<dir>`). An `error:` line → show it and stop before deleting the ticket's files. Print the kept one (or "none kept"), then the dropped ones, one line each. No ticket or nothing collected → skip.

**Done when:** neither ticket path exists, `git branch --list <branch>` prints nothing (on a close, neither does `git ls-remote --heads origin <branch>`), the ticket worktree is gone or the report names the session it goes with, and otherwise `HEAD` is on `<base>` (in a linked worktree that stays: detached at `origin/<base>`).

## 9. Report

- commits, one subject each (lint commit included)
- rebase: "up to date", or the `origin/<base>` commit it moved onto and the files whose conflicts were resolved
- tests: the script that ran, or that the project has none
- PR URL, new or reused, and whether it was merged on send; on a close, "closed without code" and the reason
- other open PRs that conflict (number, title, branch) or are not yet checked; none → "no other PR conflicts"
- board state of the card or item
- stopped dev servers, one `stopped:` line each, or why none were stopped
- deleted branches (local and, on a close, on origin), current branch or detached `HEAD`, removed paths
- the ticket worktree: removed, or the `claude rm <session id>` line that removes it with its session, and any files that block that
- the loose end kept as a to-do (or "none kept") and the dropped ones, one line each
- session branches kept and why; fast-forwarded branches
- every skipped step and why

**Done when:** the report has a line for each item above.
