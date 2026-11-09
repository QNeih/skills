# Other tracker

The board is a `board:` link or text that names neither the vault nor Jira, e.g. an Azure DevOps boards URL. A link names the tool and the project; text names at least the tool.

## Connector

Find the MCP tools for that tool (e.g. Microsoft's Azure DevOps MCP server for Azure Boards). None, or they answer unauthenticated → stop: "No connector for <tool> reachable. Add its MCP server (e.g. <the server you know for it>) or run `/mcp`, then rerun /ticket."

Every step below goes through that connector. A step the connector can't do → loose end naming the step, and go on.

## Ids

- **Number-only tracker** (items are plain numbers, e.g. Azure Boards work items): the id is the number (`1234`); the ref is the number as the tool writes it in text (`AB#1234` on Azure Boards).
- **Key tracker** (items are `KEY-123`): id and ref are both the key.

Digits only on a key tracker → `<KEY>-<digits>`, `<KEY>` from the board link or the tool's project; unknown → ask for the full id.

## Pick

The open items in the board's project assigned to Quinn, in the current iteration or sprint when the tool has one, in the tool's own rank order, without items blocked by an open item (a `Blocked by` or `Predecessor` link, or the tool's own blocked flag). Print one `<ref> · <title>` line per item and take the top one. None → print the open items of the project and ask which one; wait for the answer.

## Find

Fetch the item by its id. Not found → stop: "<ref> not found on <board>".

## Claim

- Item in an in-progress state → leave it.
- Item done or closed → stop and ask whether to reopen it.
- Else → move it to the tool's first in-progress state (e.g. `Active` or `Doing`). No assignee change.

## Branch

- Name: hotfix in the title, tags or type (any case) → `hotfix/<id>`; type Bug or Defect, or a bug tag → `bugfix/<id>`; else `feature/<id>`. On number-only trackers that gives `feature/1234`, never `feature/AB-1234`.
- Base: `develop` if it exists locally or on `origin`, else `main`.
- Nothing to note on the board: `/send` links the item through the PR's `<ref>`.

## Import

- Title: the item title. `ref:` the ref. `board:` the item's link.
- `Type:`, `Priority:`, `Tracker status:` from the item, each only if the tool has it.
- `## Description`: verbatim, as markdown.
- `## Attachments`: only when the connector can download them, into `<folder>/attachments`; look at each as for Jira (`${CLAUDE_SKILL_DIR}/JIRA.md` › Import, step 3). Else one line per attachment: "skipped: `<name>`, tracker only".
- `## Comments`: every comment, oldest first.
