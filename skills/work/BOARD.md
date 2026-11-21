# Board step

Shared by `/work`, `/ticket` and `/new-project`. Input: the project lookup's lines (`project.sh`). Output: the project's board. `${CLAUDE_SKILL_DIR}` is the folder this file is in.

`<dir>` is the lookup's `dir:` line. The **settings file** is `<dir>/.claude/project.md`; its front matter names the board.

Read the lookup's `board:` line:

- `github` with a `number:` line → the GitHub Project of that number, linked to the code repo (`repo:`).
- `jira` → Jira, with the lookup's `key:`. Tools of the claude.ai Atlassian MCP server missing or unauthenticated → stop and ask Quinn to run `/mcp` → "claude.ai Atlassian".
- `none`, `github` without a `number:` line, or `project: none` → no board yet: ask the board question.
- Any other value → that board. It is a link or text Quinn gave; a link names tool and project at once.

**Board question**, asked once, word for word:

> Where are the tasks for <project> managed? Paste a link or describe it, or reply `github` and I'll create a board.

- `github` → `bash ${CLAUDE_SKILL_DIR}/board.sh create <dir>`. It makes what is missing: the Project, its link to the code repo, the labels, the settings file. It fails → stop with its message.
  - It prints a `key:` line → the board has its **key**: ticket ids are `<KEY>-<n>`, and the Project is titled `<project> (<KEY>)`.
  - No `key:` line → run `PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/board.sh suggest-key <dir>` (the projects root is set in `~/.claude/CLAUDE.md`), then ask the key question once:
    - It prints `suggestion: <ABC>` → "Key for <project>'s ticket ids? Reply `yes` for `<ABC>`, type another key, or `none` for plain issue numbers."
    - It prints nothing → "Key for <project>'s ticket ids, e.g. `SKL` for `SKL-12`? Reply `none` for plain issue numbers."
  - The reply to the key question:
    - `yes` → `<KEY>` is `<ABC>`; run the same `create` again with `--key <KEY>` added.
    - Another key → `<KEY>` is that key in capitals; run the same `create` again with `--key <KEY>` added.
    - `none` → the board has no key: ticket ids are plain issue numbers. Nothing more to run.
- `jira` → `bash ${CLAUDE_SKILL_DIR}/board.sh set <dir> board jira`, then `set <dir> key <KEY>` with the Jira project key; ask for the key when Quinn gave none.
- A link or text → `bash ${CLAUDE_SKILL_DIR}/board.sh set <dir> board "<answer>"`. The board is the answer.

`create` and `set` write the settings file and commit nothing. With git, when `git -C <dir> status --porcelain -- .claude/project.md` prints a line: `<dir>` is on its default branch → commit that file alone and push it, so every worktree and colleague reads the same board:

```bash
git -C <dir> add .claude/project.md && git -C <dir> commit -m "Add board settings" -- .claude/project.md && git -C <dir> push -u origin HEAD
```

`<dir>` is on another branch, or the push fails → leave the file as it is and report it as could not fix, with the cause.

Then run the lookup again and use its lines.

**Done when:** the board is GitHub with a `number:`, Jira with a known `key:`, or a link or text saved in the settings file; and the settings file is committed and pushed, or reported as could not fix.
