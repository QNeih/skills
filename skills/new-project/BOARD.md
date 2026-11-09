# Board step

Shared by `/ticket` and `/new-project`. Input: the project lookup's lines (`project.sh`). Output: the project's board. `${CLAUDE_SKILL_DIR}` is the folder this file is in.

Read the lookup's `board:` line:

- `vault` → the board is the Kanban file in `board-file:`.
- `jira-candidate` → Jira, once Jira knows the project `key:`. Check it through the claude.ai Atlassian MCP server: `getVisibleJiraProjects` with `searchString: <key>`. A project whose key is exactly `<key>` → Jira. None → the key came from commit noise (`UTF-8`, `SHA-256`): ask the board question. Tools missing or unauthenticated → stop and ask Quinn to run `/mcp` → "claude.ai Atlassian".
- `none` → ask the board question.
- Any other value → that board. It is a link or text Quinn gave; a link names tool and project at once.

**Board question**, asked once, word for word:

> Where are the tasks for <project> managed? Paste a link or describe it, or reply `obsidian` and I'll create a board.

- `obsidian` → `bash ${CLAUDE_SKILL_DIR}/board.sh create "<note>"`. The board is the vault file it prints.
- A link or text → `bash ${CLAUDE_SKILL_DIR}/board.sh set "<note>" "<answer>"`. The board is the answer, saved as the note's `board:` override.

**Done when:** the board is a vault file, Jira with a known key, or a link or text that is saved in the note.
