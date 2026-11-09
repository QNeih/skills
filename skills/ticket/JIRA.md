# Jira board

Jira goes through the claude.ai Atlassian MCP server. Its tools are missing or answer unauthenticated → stop and ask Quinn to run `/mcp` → "claude.ai Atlassian".

## Setup

- `<site>`, `<cloudId>`: from `getAccessibleAtlassianResources`. The board is a link → the site in the link. Else more than one site → ask which.
- `<key>`: the board link's project key (`/projects/<KEY>/` or `/browse/<KEY>-<n>` in the URL), else the lookup's `key:`.
- `board: jira-candidate` → `${CLAUDE_SKILL_DIR}/BOARD.md` has already checked that Jira knows `<key>`.

The ticket id and ref are both `<KEY>-<n>`.

## Terms

- **Hotfix**: summary, description, a label, or the type name contains `hotfix` (any case).
- **Type buckets**:

| Bucket | Jira type names |
| --- | --- |
| bug | Bug, Defect, Bugfix, Sub-bug |
| story | Story, User Story |
| epic | Epic |
| task | Task |
| spike | Spike, Research, Investigation |

## Pick

Follow `${CLAUDE_SKILL_DIR}/PICKING.md`.

## Find

`getJiraIssue` with `fields: ["summary","description","issuetype","labels","status","fixVersions"]`. Not found → stop: "<id> not found in Jira on <site>".

## Claim

Set the fix version and the status, each only if missing.

1. **Fix version.** `getJiraIssueTypeMetaWithFields` with `projectIdOrKey: <key>`, the ticket's `issuetype.id`, `requiredFieldsOnly: false`. The result is large; extract with `jq '.fields[] | select(.fieldId=="fixVersions") | .allowedValues'`. Keep versions with `released` and `archived` both false, compared numerically:
   - Hotfix → the highest `X.Y.Z` (e.g. `6.10.4`).
   - Else → the lowest `X.Y` (e.g. `6.11`).

   The ticket already has it → skip. Else `editJiraIssue` with `fixVersions` = the ticket's current entries plus `{ "id": "<id>" }`. No candidate → loose end.
2. **Status.** `status.statusCategory.key` is `new` → `getTransitionsForJiraIssue` → the transition whose target is `In Progress` (any case) → `transitionJiraIssue`. Any other category → leave it. No such transition → loose end, with the available targets.

## Branch

| Ticket | Branch | Base |
| --- | --- | --- |
| Hotfix | `hotfix/<id>` | `main` or `master`, whichever exists |
| Bug bucket | `bugfix/<id>` | `develop` if it exists, else as for hotfix |
| Else | `feature/<id>` | `develop` if it exists, else as for hotfix |

"Exists" means locally or on `origin`. Nothing to note on the board: Jira links the branch by the key in its name.

## Import

1. Fetch: `getJiraIssue` with `fields: ["*all"]`, `expand: "renderedFields"`, `responseContentFormat: "markdown"`. `fields.comment.comments` shorter than `fields.comment.total` → fetch again with `fields: ["comment"]` until you hold all of them.
2. Download into `<folder>/attachments`, unsandboxed:
   ```bash
   python3 ${CLAUDE_SKILL_DIR}/fetch_attachments.py --site <site> --cloud-id <cloudId> <id> <folder>/attachments
   ```
   It prints one `saved` or `skipped` line per attachment. `skipped` (over 20 MB) → ask Quinn; rerun with `--max-mb <n>` if he agrees. `error:` → relay its setup hint and ask Quinn to paste each image into the chat instead.
3. **Look** at every saved file: images and PDFs with Read, `.xlsx` / `.docx` / `.pptx` with their skill. Write down what it shows: every number, label and marked spot the ticket's argument rests on. A ticket whose screenshot you have not looked at is not imported.
4. Fill the template:
   - Title: the summary. `ref:` the id. `board:` `<site>/browse/<id>`.
   - `Type:`, `Priority:`, `Tracker status:` from Jira.
   - `## Description`: verbatim; each inline image links to its local file, matched by filename via `renderedFields.description` `<img alt>`.
   - `## Attachments`: one line per `fields.attachment` entry, looked at and described, or skipped with a reason.
   - `## Comments`: all `fields.comment.total` comments; `<custom data-type="mention">@Name</custom>` → `@Name`.
