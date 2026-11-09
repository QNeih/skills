---
name: new-project
description: Set up a new or existing project — folder and local git, project note, board, sidebar group, Fork workspace — creating only what's missing. Never creates a GitHub repo.
argument-hint: "[name | clone URL], or nothing for the current folder"
disable-model-invocation: true
---

# New project

`/new-project [name|clone URL]` makes a project ready in one go. Every step checks first and creates only what's missing, so a re-run on an existing project is safe. It never creates a GitHub repo: owner and visibility stay Quinn's call.

The vault path and the projects root are set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace them). The lookup below is:

```bash
cd <folder> && VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

Keep a list of what you created and what was already there; step 8 prints it.

## 1. Folder and git

- **Empty** → the current folder: the lookup's `dir:` line run from here (the main checkout, also from a worktree). Leave it as it is: no `git init`, no move, even outside the projects root.
- **Clone URL** (`https://…`, `git@…`, `ssh://…`) → `<repo>` is the last path part without `.git`. `<projects root>/<repo>` exists → use it untouched. Else `git clone <url> "<projects root>/<repo>"`.
- **Name** → the first that exists:
  1. `VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh --note "<name>"` prints a `dir:` that exists.
  2. A folder directly under the projects root whose name matches `<name>` lowercased with spaces and hyphens removed.

  Use that folder untouched. None → `mkdir "<projects root>/<name>"` and `git -C "<projects root>/<name>" init`.

`<folder>` is its absolute path with symlinks resolved (`cd <folder> && pwd -P`) from here on.

**Done when:** `<folder>` exists, and was cloned or `git init`-ed only if it was just created.

## 2. Name

Run the lookup.

- `project: <name>` → the project has a note. Its name is the display name; say so, don't ask.
- `project: none` → suggest a name from the folder or repo name: hyphens, underscores and dots become spaces, words start upper case, all-caps parts stay (`ACME-Proto` → "ACME Proto", `acme-shop` → "Acme Shop"). Ask once: "Name for the note, sidebar group and Fork workspace: <suggestion>? Reply ok or another name."

`<name>` is used for all three.

**Done when:** Quinn confirmed `<name>`, or it came from the existing note.

## 3. Note

`<note>` is `<vault>/Projects/<name>/<name>.md`. It exists → leave its text as it is and go to the check below.

Else draft one line on what the project is from the folder's `README*` or `CLAUDE.md`. Neither → ask once: "What is it, and for which client? (skip to leave it out)". Write:

```markdown
---
tags: [project]
client: <client>
---

# <name>

<one line>

## Links

- <origin as a web link>
```

Leave out `client` unless Quinn named one, the line if Quinn skipped, and `## Links` when `git -C <folder> remote get-url origin` fails. No `status`, no `updated`, no empty sections.

**Check**: the lookup prints `project: <name>`, and `project.sh --note "<name>"` prints `dir: <folder>`. Both pass → done. Else add one property to the frontmatter and check again:

- `<folder>` is directly under the projects root and has an origin → `repo: <origin>`.
- Otherwise, or still failing → `local: <folder>`.

Still failing after `local` → print both lookups' `reason:` lines as a loose end.

**Done when:** the note exists and both lookups find each other, or the reason is printed.

## 4. Board

Run the lookup, then follow `${CLAUDE_SKILL_DIR}/BOARD.md`. It asks the board question only when the derivation fails; `obsidian` creates the board.

**Done when:** BOARD.md's done line holds.

## 5. Sidebar group

Needs the desktop tools `create_group`, `move_sessions` and `change_directory` (load them with ToolSearch). Not available → this is the CLI: skip the step and say "Sidebar group skipped: not in the desktop app."

1. `list_groups`. A group named `<square> - <name>` exists → use it.
2. Else the square is the first of 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜ that no group name starts with. All taken → ask which one. `create_group` with name `<square> - <name>`.
3. `move_sessions` with `session_ids: ["self"]` and the group's id, unless `get_session` `self` shows it is already in it.
4. `change_directory` to `<folder>`, unless the session already runs there. It takes effect when the turn ends; keep using absolute paths.

**Done when:** this session is in the group and moving to `<folder>`, or the step is skipped with the reason said.

## 6. Fork workspace

`<session>` is `~/Library/Application Support/com.DanPristupov.Fork/session.json`. Skip and say why when:

- `/Applications/Fork.app` does not exist (Fork not installed), or
- `jq -e '.workspaces | type == "array"' "<session>"` fails (no `workspaces`), or
- `jq -e --arg n "<name>" 'any(.workspaces[]; .name == $n)' "<session>"` succeeds (workspace exists).

Fork rewrites `session.json` while it runs, so edit it only while Fork is quit:

1. `pgrep -x Fork` finds it → say "Quitting Fork to add the workspace", run `osascript -e 'quit app "Fork"'` and wait until `pgrep -x Fork` finds nothing.
2. `bash ${CLAUDE_SKILL_DIR}/fork.sh "<session>" "<name>" "<folder>"`. It backs up to `session.json.bak`, then adds the workspace with `<folder>` as its only tab, shaped like an existing entry with a new UUID.
3. `open -a Fork` if it was running.

`error:` from `fork.sh` → the file is untouched. Reopen Fork as in 3, stop this step and name the manual step: "In Fork, create a workspace named <name> and open <folder> in it."

**Done when:** `fork.sh` printed `added:` and Fork runs again if it ran before, or the step is skipped or stopped with the reason said.

## 7. Specs

The project is empty when `<folder>` holds nothing but `.git`. Then offer: "Plan it now? Type `/to-spec` for a small project or `/wayfinder` for a big one, here in this session." Not empty → no offer.

**Done when:** the offer is made for an empty project, or it is not empty.

## 8. Report

Print what was created, what was already there, and what was skipped or stopped and why, one line each: folder, git, note, board, sidebar group, Fork workspace.

**Done when:** the report is printed.
