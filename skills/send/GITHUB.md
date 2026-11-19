# GitHub board

The board is a GitHub Project linked to the project's wiki repo; a ticket is an issue there. The ticket id and ref are the issue number `<n>`. The lookup's `repo:` is the wiki repo (`<owner>/<name>`).

Board writes go through `bash ${CLAUDE_SKILL_DIR}/tickets.sh`, run from inside the project.

## With a PR

Write nothing to the board. The PR body's last line `Closes <repo>#<n>` closes the issue when the PR merges, and the Project moves a closed issue to Done by itself. The ticket stays `In Progress` until the merge.

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
