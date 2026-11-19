# Spec: boards on GitHub (SKL-37)

The `gh` facts come from GitHub docs and read-only calls (2026-11-19). Dashboard, briefing and the wiki-to-brain sync are out of scope.

## Model

- Project `x` = folder `/Projects/x/` with repo `x/` and wiki repo `wiki/`.
- Board = GitHub Project (v2) linked to the wiki repo. Ticket = issue in the wiki repo. Id = issue number.
- `wiki/project.md` holds the settings: `board: github | jira`, `sentry:`, `close:`, Jira `key:`.
- Owner = the repo's owner. An org owner gives colleagues base-role access; a user owner only per-person invites.

## Skill and script changes

| Part | Today | After |
| --- | --- | --- |
| `project.sh` | vault note, board file, key from cards | name from the parent folder, wiki at `../wiki`, settings from `wiki/project.md`; prints `board: github\|jira`, `wiki:`, `owner/repo` |
| `board.sh` | `create` makes a vault board, `set` writes a note override | `create` makes wiki repo, Project, Status columns, link; `set` edits `project.md` |
| `/work` pick | unblocked `To do` cards, `#urgent` first | `gh project item-list -L 200 --query "status:Todo"`, drop issues with an open blocker, `urgent` label first |
| `/work` claim | move card to In progress | `item-edit` Status = In progress |
| `/work` branch | name from tags; `Branch` line on card | name from labels (`bug`, `hotfix`) and issue number; no stored line |
| `/work` import | card lines to `ticket.md` | issue body and comments to `ticket.md` (`gh issue view --json`) |
| `/ticket` | append a card to `To do`, next key from board | `gh issue create` in the wiki repo, label, `addBlockedBy` for `Needs`, add to Project |
| `/send` | card to Done, `PR <url>` line | PR body `Closes owner/wiki#n`; merge closes the issue; Project workflow sets Done; no board write |
| `/send` close | card to Done with reason | close issue with a comment (`--reason`) |
| `/new-project` | board question, `board.sh` | create repo and wiki repo, Project, `project.md`, folder layout |
| `/briefing` | reads boards | out of scope (SKL-36); drop `vault_merged` |
| `/note`, `/add-context`, `/sentry-fix` | project lookup | same lookup, new `project.sh` output |
| `~/.claude/CLAUDE.md` | Vault path, Boards section | remove Vault; Boards: GitHub Project in the wiki repo; Jira for construct |
| Jira path | `board: jira-candidate` | `board: jira` in `project.md`; flow unchanged |

## Setup (one time)

1. `gh auth refresh -s project` (done 2026-11-19).
2. Decide owner per project: org `lisegmbh` or `QuinnNei`.
3. Turn on the Project workflows "item closed → Done" and "PR merged → Done" (web UI only; defaults on per docs).

## Migration

1. Per project: create the wiki repo, Project, labels (`urgent`, `bug`, `hotfix`).
2. Each card becomes an issue titled with the card title: To do → open, In progress → open with Status In progress, Done → closed. Tags become labels; `Needs:` becomes blocked-by.
3. Old ids `SKL-n` are in the issue body first line (`was SKL-n`) so old branches and commits stay traceable. Old branches keep their names.
4. Archive the vault boards, then remove the vault path from `CLAUDE.md`.

## Live check (SKL-39, 2026-11-19)

Owner decision: wiki repos and Projects belong to the personal account `QuinnNei` for now. A move to the org `lisegmbh` comes later. Reason: the account is an org `member`, and the org sets `members_can_create_repositories: false`, so `gh repo create lisegmbh/...` returns HTTP 403. A member can create org Projects (empty test Project `sandbox-boards-test`, org number 10, left as is).

Sandbox (kept, private): `QuinnNei/sandbox-boards-wiki`, `QuinnNei/sandbox-boards-code`, Project https://github.com/users/QuinnNei/projects/3 (`sandbox-boards-test`).

| Behaviour | Result |
| --- | --- |
| Project linked to the wiki repo | Works: `gh project link 3 --owner QuinnNei --repo QuinnNei/sandbox-boards-wiki`. |
| Issues added to the Project | Works: `gh project item-add`. |
| Blocked-by written and read across two repos | Works. `addBlockedBy` made wiki#2 blocked by wiki#1 and by code#1 (other repo). `blockedBy` returned both with `repository.nameWithOwner` and `state` OPEN. |
| `Closes QuinnNei/sandbox-boards-wiki#2` from a squash-merged PR in the code repo | Works: wiki#2 is CLOSED (COMPLETED), `closedByPullRequestsReferences` names code PR 2. Closing worked while wiki#2 still had open blockers. |
| Item status after the cross-repo close | Wiki#2 is `Done`; wiki#1 (untouched) stays `Todo`. Something set Done by itself; the API does not say which workflow did it. |
| `Closes` from a differently owned private repo | Not testable: the org blocks repo creation, so no second owner exists. It would have shown whether a cross-owner `Closes` closes the issue and links the PR, and whether the customer-owned PR shows a link to an issue it cannot open. |

Decisions unchanged: GraphQL for blocked-by, `Closes <owner>/<wiki>#<n>` in the PR body, the Project moves a closed issue to Done. Tickets that create wiki repos use owner `QuinnNei` until the org move.

Web-UI checks for Quinn (only the UI shows them), on https://github.com/users/QuinnNei/projects/3, Workflows:
1. "Item closed" is on with Status = Done.
2. "Pull request merged" is on with Status = Done.
3. To see which one fired, turn "Item closed" off, close wiki#1, and check it stays `Todo`; then turn it back on.

## Still open after the live check

- Project under the org: create and link.
- `addBlockedBy` across repos.
- `Closes lisegmbh/wiki#n` from a PR in a differently owned private repo. Note: the customer-owned PR then shows a link to a private issue it cannot open.
- Workflows closed → Done and PR merged → Done fire for cross-repo closes.
- gh 2.90.0 lacks `--add-blocked-by`; use GraphQL or upgrade.
- `item-list` default limit is 30: always pass `-L`.
