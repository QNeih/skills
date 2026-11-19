# Board step

Shared by `/work`, `/ticket` and `/new-project`. Input: the project lookup's lines (`project.sh`). Output: the project's board. `${CLAUDE_SKILL_DIR}` is the folder this file is in.

Read the lookup's `board:` line:

- `github` → the GitHub Project linked to the wiki repo.
- `jira` → Jira, with the lookup's `key:`. Tools of the claude.ai Atlassian MCP server missing or unauthenticated → stop and ask Quinn to run `/mcp` → "claude.ai Atlassian".
- Any other value → that board. It is a link or text Quinn gave; a link names tool and project at once.
- `project: none` (no wiki yet) → ask the board question.

**Board question**, asked once, word for word:

> Where are the tasks for <project> managed? Paste a link or describe it, or reply `github` and I'll create a board.

- `github` → `bash ${CLAUDE_SKILL_DIR}/board.sh create <dir>`, `<dir>` the lookup's `dir:`. The board is the GitHub Project it makes.
- A link or text → run the same `create` (the wiki holds the settings), then `bash ${CLAUDE_SKILL_DIR}/board.sh set <wiki> board "<answer>"`, `<wiki>` the `wiki:` line `create` printed. The board is the answer.

**Done when:** the board is GitHub, Jira with a known `key:`, or a link or text saved in the wiki's `project.md`.
