# GitHub board

The board is a GitHub Project linked to the project's wiki repo; a ticket is an issue there. The ticket id and ref are the issue number `<n>`. The lookup's `repo:` is the wiki repo (`<owner>/<name>`).

Board writes go through `bash ${CLAUDE_SKILL_DIR}/tickets.sh`, run from inside the project.

## With a PR

The PR body's last line `Closes <repo>#<n>` closes the issue when the PR merges into the repo's default branch, and the Project moves a closed issue to Done by itself. The ticket stays `In Progress` until the merge.

After a merge on send, the PR's base decides:

- The base is the repo's default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`) → write nothing to the board.
- Another base (for example `develop`): `Closes` does not fire. Close the issue now:

```bash
bash ${CLAUDE_SKILL_DIR}/tickets.sh close <n> --comment "Merged in <PR url>"
```

It prints `closed: <n>`. A failure → report its output.

A PR left open → write nothing to the board.

## Close without code

```bash
bash ${CLAUDE_SKILL_DIR}/tickets.sh close <n> --comment "Closed without code: <reason>" --not-planned
```

It prints `closed: <n>`. A failure → report its output and leave the files.

## Without git

Nothing is pushed, so nothing closes the ticket on merge:

```bash
bash ${CLAUDE_SKILL_DIR}/tickets.sh close <n> --comment "Done: <$ARGUMENTS, else finished>"
```
