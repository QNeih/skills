# GitHub board

The board is a GitHub Project linked to the project's code repo; a ticket is an issue in that repo, and `<n>` is its issue number. Every call goes through `${CLAUDE_SKILL_DIR}/tickets.sh`, run from inside the project: `T="bash ${CLAUDE_SKILL_DIR}/tickets.sh"`.

- **Id** `<id>`: `<KEY>-<n>` when the lookup prints `key:` (`SKL-12`), else `<n>`. `$T` takes either form and prints `<n>`.
- **Ref**: `<repo>#<n>` (`<repo>` is the lookup's `repo:`), the form a PR's `Closes` line uses.

## Pick

`$T list` prints the unblocked `Todo` tickets, urgent first, then lowest number: one line each, `<n>`, labels and title tab-separated. Print them to Quinn as `<id> · <title>`; without a key, `#<n> · <title>`.

Nothing listed → say so and ask which ticket; wait for the answer.

## Find

`$T show <id>` prints one JSON object: `number`, `title`, `body`, `state`, `status`, `labels`, `comments` (`author`, `body`), `blockers` (`ref`, `state`). It fails → stop with its message.

A blocker with `state` `OPEN` → tell Quinn and ask whether to work on it anyway.

## Claim

- `status` is `In Progress` → leave it.
- `state` is `CLOSED`, or `status` is `Done` → stop and ask whether to reopen it.
- Else → `$T status <id> in-progress`. It fails → report it as could not fix, with its message.

No assignee.

## Branch

- Name: a `hotfix` label → `hotfix/<id>`; a `bug` label → `bugfix/<id>`; else `feature/<id>` (`feature/SKL-12`; without a key, `feature/12`).
- Base: `develop` if it exists locally or on `origin`, else `main`. A PR into `develop` does not close the issue through `Closes`; `/send` closes it after the merge.
- Nothing to note on the board: `/send` links the ticket through the PR's `Closes <ref>` line.

## Import

- Title: the issue title. `ref:` the ref. `board:` `https://github.com/<repo>/issues/<n>`.
- `Type:` bug, hotfix or feature, as for the branch name; `Tracker status:` the Project's `status`; no priority.
- `## Description`: `body`, verbatim.
- `## Attachments`: inline images stay links; no downloads.
- `## Comments`: every entry of `comments`, in order, as `### <number> · <author>` (no date).
