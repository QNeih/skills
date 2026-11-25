---
name: send
description: Ship the current branch on any board — commit by concern, fix its leftovers, rebase, lint, test, push, open or reuse the PR, move the ticket (on GitHub, the PR's `Closes` line closes it on merge), then clean up the branch, the ticket worktree and the ticket's files. A ticket branch with nothing on it is closed instead; the ticket closes with the reason, same cleanup. Closes the flow /work starts.
argument-hint: "[draft] [notes for the commit and PR wording, or the close reason]"
---

# Send

`/send` ships the current branch: commit, fix its leftovers, rebase onto the base branch, lint, test, push, open or reuse the PR, move the ticket on its board (GitHub: the PR body's `Closes` line closes it on a merge into the default branch; after a merge on send into another base, `/send` closes it), then write the ticket's decision note into the brain, stop the ticket's dev servers and delete the branch, the ticket worktree and the ticket's `.scratch/` and `.handoffs/` files. A ticket whose branch has nothing on it is **closed** instead: no commit, push or PR, the ticket closes with the reason, and the same cleanup runs. Typing `/send` is Quinn's go-ahead to commit, push and delete; there is no review step. Every step runs unless it says stop.

`$ARGUMENTS`: the word `draft` → open the PR as draft. Other text → context for the commit and PR wording, or the reason on a close; without git, it may name the ticket id.

## Text rules

For commit messages, the PR title and body, and anything written to a tracker:

- Describe the change, nothing else. Each message ends on its last line of content: this skill overrides the harness attribution, so no `Co-Authored-By` trailer, no "Generated with" footer, no tool, IDE or assistant names.
- PR body: `## Summary` bullets first, the tracker's link line last (step 7). A testing checklist only if `$ARGUMENTS` asks for one.

## 1. Project and ticket

The projects root is set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace it). Run from the current folder:

```bash
PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

`<dir>` is its `dir:` line: the main checkout, or the project folder without git. **Git** means `git -C <dir> rev-parse` succeeds. Its `board:` line is the board: `github`, `jira`, or another tracker's link or text; `repo:` is the GitHub board's repo (`owner/name`, the code repo). `board: none` or `project: none` → no board from the lookup; go on.

Find the ticket. Its **ticket files** are `.scratch/<id>-<slug>/ticket.md` (title line `# <id>: …`, then `ref:`, `base:`, `board:`, and on Jira and other boards `branch:`) and `.handoffs/HANDOFF-<id>.md`. Note where they were found: step 10 deletes them there.

- **Git**: a session started in the main checkout that works on its ticket in the ticket worktree `/work` made (`<dir>/.claude/worktrees/<id>`) → `cd` there first; steps 1–10 run in it. Look for the ticket files in the worktree this session now works in, then in `<dir>` (tickets started before `/work` wrote them into the worktree keep them there). `<branch>` = `git branch --show-current`. The `ticket.md` with the line `branch: <branch>` is the ticket. On GitHub the ticket stores no branch: the id is the last path segment of `<branch>` (`feature/SKL-12` → `SKL-12`; on a board without a key `feature/12` → `12`), and its folder is `.scratch/<id>-*` in the worktree, else in `<dir>`.
  - None → fallback for hand-cut branches: `<branch>` contains `[A-Z][A-Z0-9]+-[0-9]+` → that is the id and the ref, the board is the lookup's; `<branch>` ends in `/<digits>` on a GitHub board → that number is the id.
  - Still none → no ticket: the PR goes out without one, no board move, no ticket files deleted. Say so.
- **No git**: the ticket files are in `<dir>`. The `ticket.md` files with `branch: none` or no `branch:` line. `$ARGUMENTS` names an id → that one. Else one file → it. Else the ones whose ticket is `In Progress` on their board (GitHub: `bash ${CLAUDE_SKILL_DIR}/tickets.sh show <n>` prints `status`); exactly one → it, otherwise list them and ask. None → stop and print this line as is: `Nothing to send: no ticket in <dir>/.scratch.`

The board is the lookup's `board:`; `ticket.md`'s `board:` link names the Jira site and project. A GitHub board is described in `${CLAUDE_SKILL_DIR}/GITHUB-SEND.md`.

**Decisions**, with a `ticket.md`: step 9 copies its `## Decisions` section into the brain and step 10 deletes the file, so the section is settled now, before anything is committed.

```bash
bash ${CLAUDE_SKILL_DIR}/decision-note.sh --check --ticket <ticket.md>
```

- `decisions: ok` or `decisions: none` → go on.
- `decisions: empty`, or `error: decision line …` → follow `${CLAUDE_SKILL_DIR}/DECISIONS.md` (it fills an empty section and repairs a refused line, and stops for Quinn when a reason is unknown), then run the check again.

**Done when:** `<dir>`, git or not, and the ticket (id, ref, board) or "no ticket" are known, and with a `ticket.md` the check printed `decisions: ok` or `decisions: none`.

Without git, go to step 8.

## 2. Preflight

1. No `origin` remote → stop: "no origin to push to". `<host>` = the host in `git remote get-url origin` (`git@<host>:…`, `https://<host>/…`, `ssh://[user@]<host>/…`); a local path is its own `<host>`. Print one line before any other step: `Host: <host>, PR` for `github.com`, else `Host: <host>, push only`. A **push-only** send pushes the branch and opens no PR: it ends at step 6, with no `gh pr` or `gh label` call and without steps 7–10. A close (item 8) pushes no code, so it runs the same on every host.
2. `git fetch origin` (`cannot open '.git/FETCH_HEAD'` → rerun unsandboxed).
3. `<base>`: `ticket.md`'s `base:`. Else a `hotfix/` branch → `main` or `master`, whichever is on `origin`; else `develop` if `origin/develop` exists, else `main` or `master`.
4. `git diff --cached --quiet` fails → stop and ask: unstage (`git restore --staged .`) or say how to treat the staged hunks.
5. **Port change**: `git diff -- .claude/launch.json` prints a diff, and every changed line differs from the line it replaces only in a number → `git restore .claude/launch.json`. That is a dev server's port moved for this session: it is never committed, and left in place it blocks the worktree's removal in step 10. The diff changes anything else → stop and ask which lines to commit.
6. **Change set**: `git status --porcelain --untracked-files=all`, minus every path under `.scratch/` or `.handoffs/`.
7. **Branch commits**: `git rev-list origin/<base>..HEAD`, pushed or not. Commits already on `origin` still need their PR, board move and cleanup.
8. Change set and branch commits both empty:
   - No ticket → stop and print this line as is: `Nothing to send: <branch> has no changes against <base>.`
   - A ticket → this is a **close**. Reason: `$ARGUMENTS` without the word `draft`; empty → ask Quinn for one line and wait, changing nothing before the answer. Skip steps 3–7 and go to step 8 (Board); of step 4, only collect the observations: they are the close's follow-ups, handled in step 8.

**Done when:** the `Host:` line is printed, no hunks are staged, `<base>` is known, and the change set and branch commits are listed, or a close has its reason.

## 3. Commit

Change set empty → skip and say "no uncommitted changes; sending the branch commits".

1. Read `git diff`, the untracked files, and `git log -10 --format=%s` for the repo's subject style.
2. Plan one commit per concern: refactor apart from behaviour, unrelated areas apart; prep (renames, moves) before what depends on it. Show the plan: ordered subjects, paths or hunks each.
3. Per commit: `git add <paths>`. A file split across commits → write that commit's hunks to a patch in a temp dir and `git apply --cached <patch>`. Then `git commit -m "<subject>" -m "<body>"`: subject imperative, about 50 chars, no period; body 1–4 lines the staged diff supports.

**Done when:** `git status --porcelain` shows only `.scratch/` and `.handoffs/` paths, and every planned subject is in `git log`.

## 4. Leftovers

A **leftover** is something still wrong or unfinished on the branch. Collect them from the handoff and from this session's reports, its sub-agents' reports included. Sort each one:

- **Own**: the ticket's change broke it or left it unfinished.
- **Breaking**: a build, a lint run, a test or data fails or is lost now, inside or outside the ticket.
- **Observation**: it breaks nothing and lies outside what the ticket's change touched. In doubt → own.

Fix every own and breaking leftover now, each in its own commit on `<branch>`, so Quinn can revert one alone. A sizable fix (several files, or the cause is still unknown) → hand it to a subagent with the Agent tool: the leftover, the worktree path, "commit the fix as one commit on `<branch>`", and that its commit message describes the change only: no `Co-Authored-By` trailer, no "Generated with" footer, no tool, IDE or assistant names.

A fix that fails → discard its uncommitted changes and note the leftover as **could not fix**, with its cause, for the report.

A **follow-up** is a leftover that stays unfixed: an observation, or a could not fix. Step 7 files each one as a ticket or lists it for Quinn (on a close, step 8 does). A stop before step 7 leaves them unfiled: the report lists them, and the next `/send` handles them.

None collected → say "no leftovers" and go on.

**Done when:** every collected leftover is fixed in its own commit or is a follow-up (a could not fix has its cause), and the tree is clean as after step 3.

## 5. Rebase, lint and test

In this order. A lint or test run that exits non-zero is a breaking leftover: fix it as step 4 says, then run Lint and Test again, until both exit 0. Could not fix → stop, and show the output and the cause. A stop in any of the three means nothing is pushed.

**Rebase**: `git rebase origin/<base>`, so the PR can't conflict with what merged since the branch was cut.

- Conflict → resolve it with the Skill tool `resolving-merge-conflicts`. A hunk that `ticket.md` and both sides leave undecided → `git rebase --abort`, stop and name the conflicting files.
- It fails for another reason → stop and show the output.
- `git rev-list origin/<base>..HEAD` prints nothing afterwards (`<base>` already holds every change) → the branch has nothing on it: apply step 2's rule for an empty change set with no branch commits.

**Lint**

Paths: `git diff --name-only origin/<base>...HEAD` that still exist. This covers commits made before `/send` too.

1. For each path, walk up to the nearest directory (not above `git rev-parse --show-toplevel`) whose `package.json` has a `lint-fix` script. Run `npm run lint-fix` once in each distinct directory.
2. Non-zero exit → a breaking leftover (above).
3. No such directory → say so and go on.
4. `git status --porcelain` shows changes outside `.scratch/` and `.handoffs/` → commit them all as one commit, `Apply lint fixes`.

**Test**: at `git rev-parse --show-toplevel`, the first of `test.sh` and `tests/run.sh` that exists → `bash <script>` from there. Non-zero exit → a breaking leftover (above). Neither exists → say "no test.sh or tests/run.sh: tests not run" and go on.

**Done when:** `git merge-base --is-ancestor origin/<base> HEAD` succeeds, every lint-fix run and the test script exited 0 (or the project has no test script), and the tree is clean again.

## 6. Push

1. `git push --force-with-lease -u origin HEAD` (`Operation not permitted` → rerun unsandboxed). The lease is there because the rebase may have rewritten commits that `/work` already pushed. Fails → stop and show the output.
2. Push-only (step 2) → the send ends here: print this line as is, `PR on <host> not supported`, then the report (step 11). The branch, the ticket and its files stay as they are.

**Done when:** `origin/<branch>` equals `HEAD`, and `<host>` is `github.com` or the stop is printed.

## 7. PR

`gh pr view --json url,state,body`: `state` is `OPEN` → reuse it; a GitHub board's body that lacks the `Closes` line gets it as the last line, through `gh pr edit --body`. Otherwise (no PR, or only merged or closed ones):

```bash
gh pr create --base <base> --assignee @me [--label <label>] --title "<title>" --body "<body>" [--draft]
```

- `--draft`: only when `$ARGUMENTS` has the word `draft`.
- Label from `<branch>`'s prefix, case-insensitive: `hotfix/` → `hotfix`; `bugfix/` → `bugfix`; `feature/` → `feature`, else `enhancement`. Take the first of these that `gh label list` shows. None exists, or another prefix → open without a label and say so.
- Title: `<ref>: <gist of the change>`; on GitHub `<id>: <gist of the change>` (`SKL-12: …`); no ticket → the gist alone.
- Body: `## Summary` bullets from `ticket.md` and the commit subjects, then one link line in the tracker's syntax, last: GitHub → `Closes <repo>#<n>` (`<repo>` the lookup's `repo:`; merging into the default branch closes the ticket); Jira → `Jira: <link>` (the `board:` link; without `ticket.md`, `https://<site>/browse/<ref>`, site from `getAccessibleAtlassianResources`); Azure Boards → the ref alone (`AB#1234`), which links it; another tracker → the item's link; no ticket → no link line.

**Follow-ups**, once the PR exists. A follow-up that a `Follow-up:` line of the PR body already describes was handled by an earlier `/send`: skip it; the `<m>` of that line's ref is its ticket, for the report. For each other one, by the lookup's lines:

- `board: github` with a `number:` line → file its ticket as `${CLAUDE_SKILL_DIR}/GITHUB-SEND.md` says under "Follow-up tickets". Its line: `Follow-up: <repo>#<m> <what, where>`.
- Anything else (Jira, another tracker, no board) → its line: `Follow-up: <what, where>`. Step 11 asks Quinn about it.

Then `gh pr edit <url> --body` puts the new lines before the link line, one per follow-up. The ref follows `Follow-up:` directly, with no `Closes`, `Fixes` or `Resolves` in the line, so the merge leaves the filed ticket open.

**Merge on send**: a `CLAUDE.md` rule says to merge this repo's PRs on send, and the PR isn't a draft → `gh pr merge <url> --squash --delete-branch`. It fails → stop and show the output; the board move and cleanup don't run (GitHub: a merge into the default branch closes the ticket by itself).

**Conflicting PRs**: `gh pr list --state open --limit 100 --json number,title,headRefName,mergeable`. Every PR whose `headRefName` is not `<branch>` and whose `mergeable` is `CONFLICTING` goes into the report with its number, title and branch. `UNKNOWN` (GitHub works it out only once asked, so this is usual right after a merge) → run the list again right before the report (step 11); still `UNKNOWN` → report that PR as not yet checked. Their branches stay as they are: each one is rebased by `/send` in its own ticket's session.

**Done when:** you hold the URL of an `OPEN` PR for `<branch>` (or, merged on send, a `MERGED` one), or the reason there is none; every follow-up has exactly one `Follow-up:` line in the PR body, on a GitHub board with its ticket; and every other open PR is noted as conflicting or `UNKNOWN`, or left out as mergeable.

## 8. Board

Runs after a successful push on a host that takes a PR, even if the PR step failed; on a close, right after step 2; without git, right after step 1. No ticket → skip and say so.

- **GitHub**: follow `${CLAUDE_SKILL_DIR}/GITHUB-SEND.md`. With a PR, the board write is only the close after a merge into a non-default base.
- **Jira** → `Code Review`, through the claude.ai Atlassian MCP (`cloudId` from `getAccessibleAtlassianResources`):
  1. `getJiraIssue`: status already `Code Review` → done.
  2. `getTransitionsForJiraIssue` → the transition whose target status is `Code Review` (any case) → `transitionJiraIssue`.
  3. No such transition → report the available target statuses. MCP tools missing or unauthenticated → tell Quinn to run `/mcp` → "claude.ai Atlassian".
- **Another tracker** → through its connector, move the item to its review state (with a PR) or its done state (without git), and add the PR link. No connector reachable → name the missing one.
- **Close on Jira or another tracker** (instead of the Jira and Another tracker bullets): the state comes from `close:` in the settings file `<dir>/.claude/project.md`.
  - No `close:` line → ask Quinn once: "Which state does closing a ticket without code move it to in <project>? Name the state, or `leave`." Save the answer as `close: "<answer>"` in that file's front matter, before the closing `---`. With git and `<dir>` on its default branch → commit that file alone there and push it; another branch, or the push fails → report it as could not fix, with the cause. No settings file (`board: none` or `project: none`) → ask, don't save.
  - `leave` → don't move the item; report "close <ref> on the tracker yourself" with its link.
  - Else move the item to that state (Jira: the transition whose target status matches, any case) and add the comment `Closed without code: <reason>`. No such transition → report the available target statuses and change nothing.

**Follow-ups on a close**, once the ticket is closed or moved (or Quinn answered `leave`); until then they stay unfiled, so a second `/send` files none twice. `board: github` with a `number:` line → file each one's ticket as `${CLAUDE_SKILL_DIR}/GITHUB-SEND.md` says under "Follow-up tickets". Anything else → step 11 asks Quinn about them.

**Done when:** the ticket shows the new state, or the reason it doesn't is reported; on a close, every follow-up is filed or kept for step 11's question; on GitHub, a PR merged into a non-default base has its ticket closed, and any other PR caused no board write.

## 9. Decision note

A **decision note** is a source in the brain's `raw/<Name>/` folder: the ticket's decision lines, and the ADRs and glossary entries the branch added or changed. This step runs with a ticket, when:

- **Git**: step 7 ended with an `OPEN` PR or one it merged; on a close, step 8 closed or moved the ticket (or Quinn answered `leave`).
- **No git**: step 8 left the ticket closed (or the item done).

Otherwise skip and say why. With git, run it where steps 2–8 ran, on `<branch>`, before step 10's `git fetch`: the ADR and glossary diff needs `origin/<base>` as it was before a merge on send.

```bash
VAULT=<vault> bash ${CLAUDE_SKILL_DIR}/decision-note.sh --ticket <ticket.md> --project <project> [--base <base>] [--close "<reason>"]
```

- `<vault>`: the `Vault:` path in `~/.claude/CLAUDE.md`. `<project>`: the lookup's `project:` line; `none` → the name of `<dir>`.
- `--base <base>`: with git, so the note copies every ADR and glossary entry the branch added or changed. `--close`: on a close, with its reason, which the script adds as one more decision line.
- `note: <path>` → written. The vault stays uncommitted: `brain-sync` commits it daily.
- `note: none` → nothing to write; keep its `reason:` line for the report.
- `error: decision line without <label> in <ticket.md>: <line>` → the script wrote no note (a line changed since step 1's check). Repair it as `${CLAUDE_SKILL_DIR}/DECISIONS.md` says and rerun the script.
- Another `error: <cause>` → could not fix, with that cause.

**Done when:** the script printed a `note:` line or an `error:` no rewrite can clear, or the skip is noted.

## 10. Clean up

- **Git**: runs when step 7 ended with an `OPEN` PR or one it merged, even if step 8 failed; on a close, only when step 8 closed or moved the ticket (or Quinn answered `leave`), since nothing else records the ticket. Otherwise skip and say why.
  1. `git rev-parse HEAD` differs from `git rev-parse @{u}` → stop: the remote doesn't hold every local commit. Merged on send → skip this check (`--delete-branch` removed the upstream); `git fetch origin` instead, so `origin/<base>` has the merge. Close → skip this check.
  2. Leave `<branch>`. Linked worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`) → `git switch --detach origin/<base>`, since `<base>` is usually checked out in the main checkout. Otherwise `git switch <base>`, then `git pull --ff-only`. Switch fails → stop and show the output.
  3. `git branch -D <branch>` (`-D` because the PR may not be merged yet; its commits are on `origin/<branch>`). Close and `origin/<branch>` exists → also `git push origin --delete <branch>`.
  4. Stale session branches: `git for-each-ref --format='%(refname:short) %(worktreepath)' 'refs/heads/claude/*' 'refs/heads/worktree-*'`. For each one with no worktree path and no output from `git rev-list -1 <name> --not --remotes` (every commit is on `origin`) → `git branch -D <name>`. The others stay; name them in the report.
  5. Each of `main`, `master`, `develop` that exists locally and is checked out in no worktree → `git fetch origin <name>:<name>`. Not a fast-forward → report it and go on.
  6. Dev servers, with a ticket: the ticket worktree `<dir>/.claude/worktrees/<id>` exists → `bash ${CLAUDE_SKILL_DIR}/stop-servers.sh <dir>/.claude/worktrees/<id>`. It stops every process that listens on a TCP port from inside that folder and the compose projects its run file starts, and prints one `stopped:` line each. A `skipped:` line → put it in the report. An `error:` line → show it and stop. No ticket worktree (the ticket was worked in the main checkout) → stop nothing and say so: a server listening there may be one Quinn runs.
- **No git**: runs when step 8 left the ticket closed (or the item done). Otherwise keep the files and say why.

Then, with a ticket, delete its ticket files where step 1 found them (untracked, so `rm -rf`): its `.scratch/<id>-<slug>/` folder and `.handoffs/HANDOFF-<id>.md`. A `.scratch/` or `.handoffs/` folder left empty → remove it. Other tickets' files stay.

Last, with git and a ticket: the ticket worktree `<wt>` = `<dir>/.claude/worktrees/<id>`. It doesn't exist → skip. Else run `claude agents --json --all --cwd <dir>`:

- It lists a session with `kind` `background` and `cwd` `<wt>` (this session, when it was started with `claude --bg -w <id>`) → leave `<wt>`: a session cannot remove the folder it runs in, so the worktree goes with the session. `git status --porcelain` in `<wt>` prints anything → name those files in the report: `claude rm` refuses a worktree with uncommitted changes. Report the line `claude rm <session id>`, the listed session's `id`; Quinn removes the session (dashboard: `a a`), and that deletes the worktree.
- No such session → `cd <dir> && git worktree remove <wt>`, without `--force`. Git refuses (untracked or modified files) → stop and name the files from its output. Every later command runs from `<dir>`.

**Done when:** neither ticket path exists, `git branch --list <branch>` prints nothing (on a close, neither does `git ls-remote --heads origin <branch>`), the ticket worktree is gone or the report names the session it goes with, and otherwise `HEAD` is on `<base>` (in a linked worktree that stays: detached at `origin/<base>`).

## 11. Report

- commits, one subject each (leftover fixes and lint commit included)
- rebase: "up to date", or the `origin/<base>` commit it moved onto and the files whose conflicts were resolved
- tests: the script that ran, or that the project has none
- PR URL, new or reused, and whether it was merged on send; on a close, "closed without code" and the reason
- decisions: "from the ticket", or the decision lines step 1 wrote, one each, or that it wrote `none` because the work held no choice; and each line it rewrote
- decision note: its path, or "no decision note" and the `reason:` or `error:` line
- other open PRs that conflict (number, title, branch) or are not yet checked; none → "no other PR conflicts"
- board state of the ticket: GitHub with a PR, "closes on merge" (or "closed" once merged); else its new state
- stopped dev servers, one `stopped:` line each, or why none were stopped
- deleted branches (local and, on a close, on origin), current branch or detached `HEAD`, removed paths
- the ticket worktree: removed, or the `claude rm <session id>` line that removes it with its session, and any files that block that
- what it could not fix, each with its cause, or "nothing left unfixed"
- follow-ups, one line each, or "no follow-ups": with a filed ticket → `<KEY>-<m>: <what>` with the lookup's `key:` (`SKL-31: …`; without a key `#<m>: …`), and whether this run or an earlier one filed it; after a stop before step 7 → "not filed: no PR yet"; on a board that is no GitHub Project → listed, and the report's last line asks Quinn: `File a ticket for which of these follow-ups?`
- session branches kept and why; fast-forwarded branches
- every skipped step and why

**Done when:** the report has a line for each item above.
