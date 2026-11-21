# Skills audit, November 2026

Audit of 2026-11-21, covering this repo's skills only; an overlap with an installed third-party skill counts against the repo skill. It starts with removing `/add-context`: the brain now takes all project context, so nobody files sources into a code repo's `context/` folder by hand.

| Skill | Verdict | Reason | Change |
| --- | --- | --- | --- |
| `add-context` | remove | The brain takes all project context; the shared wiki is fed from the brain daily. | Skill, script test and README row removed (this PR). BGH-Proto's `context/` moves into the brain (BGH-55). |
| `ask` | remove | Plan mode and plain questions answer codebase questions just as well. | Skill and README row removed (this PR). |
| `build` | change | Named a vault board as the parent ticket's home; boards are GitHub Projects or Jira now. | Names the board as a GitHub Project or Jira (this PR). |
| `cv-update` | keep | Still the weekly CV check; no overlap. | none |
| `dashboard` | keep | Still the one way to open the dashboard; no overlap. | none |
| `dependabot-review` | keep | Still needed for Dependabot PRs; no overlap. | none |
| `new-project` | change | No vault board is left to migrate, and every project's board is a GitHub Project. | Vault-board migration script, its script test and its spec section removed (this PR). Always creates a GitHub board, without the board question (SKL-79). |
| `send` | keep | Closes the ticket flow. Its ban on the `Co-Authored-By` trailer is deliberate: Quinn wants it on no commit. | none |
| `sentry-fix` | keep | Still the Sentry fix flow; no overlap. | none |
| `ticket` | keep | Still the way to add a ticket to a board. | none |
| `wiki` | keep | Sets up the shared wiki fed daily from the brain (`raw/<Project>` → wiki task → wiki repo). | none |
| `work` | keep | Still starts the ticket flow. | none |

## Cross-cutting

- Copies of `project.sh`, `tickets.sh`, `board.sh`, `BOARD.md` and `verify.md` in several skills stay: they are byte-identical, and `tests/shared-copies.sh` fails when one drifts.
- `skills/dashboard/start.sh` and `skills/work/fetch_attachments.py` get script tests, and `tests/eval-triggers.py` goes with its `tests/run.sh` line (SKL-78).
- Stale docs fixed in this PR: the boards spec no longer names `/note` or `/add-context`, and the README no longer lists the Microsoft 365 connector that only `/add-context` needed.
