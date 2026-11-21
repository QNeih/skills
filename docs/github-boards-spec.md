# Spec: boards on GitHub

A project's board lives in its code repo. The `gh` facts come from GitHub docs and from the live check below.

## Model

- **Project** `x` = one code repo. Its main checkout is `<projects root>/x` (flat) or `<projects root>/x/x` (nested, in a project folder of the same name). The project's name is the checkout folder's name.
- **Board** = GitHub Project (v2) linked to the code repo, titled `<name> (<KEY>)`, e.g. `skills (SKL)`. Without a key the title is `<name>`.
- **Ticket** = issue in the code repo. `<n>` is the issue number.
- **Id** = `<KEY>-<n>` when the board has a key (`SKL-12`), else `<n>`, shown as `#<n>`. Branches are `feature/<id>`, `bugfix/<id>`, `hotfix/<id>`; a ticket is shown as `<id> · <title>`.
- **Ref** = `<repo>#<n>`, the form a PR's `Closes` line uses.
- **Settings file** = `<main checkout>/.claude/project.md`, committed on the default branch. Front matter:

  | Key | Meaning | Default |
  | --- | --- | --- |
  | `board` | `github`, `jira`, or another tracker's link or text | `github` |
  | `project` | the Project's number | none |
  | `owner` | the Project's owner | the repo's owner |
  | `key` | the key in the ticket ids (GitHub) or the Jira project key | none |
  | `repo` | `owner/name` of the repo holding the issues | the checkout's origin |
  | `sentry`, `close` | per-project choices of `/sentry-fix` and `/send` | none |

- A **wiki** repo is optional and holds pages only. In the nested layout it may sit next to the checkout as `<name>/wiki`. No board script reads or creates it.
- An org owner gives colleagues base-role access to the Project; a user owner only per-person invites.

## Scripts

Copies of one script are identical in every skill that carries it; `tests/shared-copies.sh` compares them.

| Script | Behaviour |
| --- | --- |
| `project.sh` | The lookup. Finds the main checkout from any folder inside it (nested when the checkout's parent folder has its name, else flat) or by `--name` under the projects root. Prints `dir:`, `project:`, `wiki:` (nested, when the folder exists), `board:`, `repo:`, `number:`, `owner:`, `key:`. Without a settings file: `board: none` and a `reason:`. Outside a checkout and without a settings file: `project: none` and a `reason:`. |
| `board.sh create` | Makes what is missing: the Project (found again by the `project` setting, else by title), its link to the code repo, the labels `urgent`, `bug`, `hotfix`, the settings file. Commits nothing. |
| `board.sh set` | Sets one line of the settings file; creates the file when missing. |
| `tickets.sh` | `list`, `show`, `status`, `create`, `block`, `close` on issues in the code repo and their Project items. Takes `<n>`, `#<n>` or `<KEY>-<n>`; prints `<n>`. |

## Skills

| Skill | On a GitHub board |
| --- | --- |
| Board step (`BOARD.md`) | No board yet → asks where the tasks are managed; `github` → `board.sh create`, then asks for a key when the board has none; the settings file is committed on the default branch and pushed. |
| `/work` pick | `tickets.sh list`: `Todo` items without an open blocker, `urgent` label first, then lowest number. |
| `/work` claim | Status → In Progress. No assignee. |
| `/work` branch | Name from the labels (`bug`, `hotfix`) and the id. Nothing stored on the ticket. |
| `/work` import | Issue body and comments into `ticket.md`. |
| `/ticket` | `tickets.sh create`: issue in the code repo, labels, blocked-by for Needs, added to the Project. |
| `/send` | PR body ends with `Closes <repo>#<n>`. A merge into the default branch closes the issue and the Project sets Done. A merge into another base closes nothing, so `/send` closes the issue. |
| `/send` close | Closes the issue as not planned, with the reason as a comment. |
| `/new-project` | Folder, code repo, board step. A new project is flat. A wiki comes from `/wiki`, on request. |
| `/note`, `/add-context`, `/sentry-fix` | Use the lookup's `dir:` and `project:`; `/sentry-fix` reads `sentry:` from the settings file. |
| Jira | `board: jira` and `key:` in the settings file; flow unchanged. |

## Setup (one time)

1. `gh auth refresh -s project`.
2. Per Project, turn on the workflows "Item closed → Done" and "Pull request merged → Done" (web UI only; on by default per the docs).

## `gh` facts

Verified on 2026-11-19 in the sandbox `QuinnNei/sandbox-boards-wiki`, `QuinnNei/sandbox-boards-code`, Project https://github.com/users/QuinnNei/projects/3 (private, personal account), and on 2026-11-20 by read-only calls against `QNeih/skills`:

| Behaviour | Result |
| --- | --- |
| Project linked to a repo | Works: `gh project link <number> --owner <owner> --repo <owner>/<name>`. |
| Reading which Projects a repo is linked to | Works: GraphQL `repository.projectsV2` returns `number`, `title` and `owner.login`. `board.sh create` links only when the Project is not in that list. |
| Issues added to the Project | Works: `gh project item-add`. |
| Blocked-by written and read, also across repos | Works. `addBlockedBy` (GraphQL; `gh` has no flag for it) links two issues; `blockedBy` returns each blocker with `repository.nameWithOwner` and `state`. |
| `Closes <owner>/<name>#<n>` from a squash-merged PR | Works: the issue is CLOSED (COMPLETED) and `closedByPullRequestsReferences` names the PR. Closing worked while the issue still had open blockers. Checked with the PR and the issue in two repos; same-repo closing is GitHub's documented base case. |
| Item status after the close | The closed issue's item is `Done`; untouched items stay `Todo`. |
| `gh project item-list`, `gh project list` | Default limit 30: always pass `-L`. |
| Org `lisegmbh` | An org member can create org Projects, and cannot create repos there (`members_can_create_repositories: false`, HTTP 403). |

Not verified:

- Which Project workflow ("Item closed" or "Pull request merged", both Status = Done) set Done after the close; only the web UI shows it.
- A Project owned by another account than the repo's owner (`owner` setting): the link and the item writes.
- Whether `gh project link` on an already linked Project is a no-op; `board.sh create` avoids the call.
