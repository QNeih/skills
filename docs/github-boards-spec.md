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

## Open for a live test (build ticket)

- Project under the org: create and link.
- `addBlockedBy` across repos.
- `Closes lisegmbh/wiki#n` from a PR in a differently owned private repo. Note: the customer-owned PR then shows a link to a private issue it cannot open.
- Workflows closed → Done and PR merged → Done fire for cross-repo closes.
- gh 2.90.0 lacks `--add-blocked-by`; use GraphQL or upgrade.
- `item-list` default limit is 30: always pass `-L`.
