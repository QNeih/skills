---
name: new-project
description: Set up a new or existing project — folder layout, project repo, wiki repo, GitHub board, sidebar group, optional brain wiki — creating only what's missing.
argument-hint: "[name | clone URL], or nothing for the current folder"
disable-model-invocation: true
---

# New project

`/new-project [name|clone URL]` makes a project ready in one go. Every step checks first and creates only what's missing, so a re-run on an existing project is safe.

A project `x` is the folder `<projects root>/x/` with two private repos: `x/` (the project repo) and `wiki/` (the wiki repo, which holds the board and `project.md`). The projects root is set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace it). The lookup below prints the project's lines:

```bash
cd <folder> && PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh
```

Keep a list of what you created and what was already there; step 6 prints it.

## 1. Folder and repo

`<name>` is the project folder's name, `<project folder>` is `<projects root>/<name>` and `<repo>` is `<project folder>/<name>`.

- **Empty** → the current folder: the lookup's `dir:` line run from here (the main checkout, also from a worktree). Its parent is `<project folder>`. A parent whose name differs from the folder's own → stop: "<dir> is not in the layout `<name>/<name>`: move it first."
- **Clone URL** (`https://…`, `git@…`, `ssh://…`) → `<name>` is the last path part without `.git`. `<repo>` exists → use it untouched. Else `git clone <url> "<repo>"`, creating the parent folder first.
- **Name** → `<repo>` exists → use it untouched. Else `mkdir -p "<repo>"` and `git -C "<repo>" init`.

A repo made by `git init` has no origin: ask once "Owner for the new repos: <owner>? (a GitHub user or org)". Then `gh repo create <owner>/<name> --private --source "<repo>" --remote origin`, and remember `<owner>`.

`<repo>` is its absolute path with symlinks resolved (`cd <repo> && pwd -P`) from here on.

**Done when:** `<repo>` exists inside `<name>/`, and has an origin or a remembered `<owner>`.

## 2. Board

Run the lookup from `<repo>`.

- `board: jira`, or `board:` a link or text → the board exists; go to the next step.
- `board: github` → it exists when `number:` and `repo:` print; else run the create below.
- `project: none` → run the create below. `<repo>` has no wiki yet: the one command makes the wiki repo, the Project, the labels, the `wiki/` clone and `wiki/project.md`, so an existing repo gets its board in this one step.

```bash
bash ${CLAUDE_SKILL_DIR}/board.sh create "<repo>" [--owner <owner>]
```

Pass `--owner` only when `<repo>` has no origin; otherwise the wiki and the Project get the origin's owner. The script commits `wiki/project.md` and pushes it. It prints `wiki:`, `repo:`, `number:` and `owner:`; rerun the lookup and use its lines.

Tasks that live elsewhere, on Quinn's word: after `create`, `bash ${CLAUDE_SKILL_DIR}/board.sh set "<wiki>" board "<link, text or jira>"`, and for Jira also `set "<wiki>" key "<KEY>"`.

**Done when:** the lookup prints `project: <name>` with `board:`, and for `github` also `number:` and `repo:`.

## 3. Sidebar group

Needs the desktop tools `create_group`, `move_sessions` and `change_directory` (load them with ToolSearch). Not available → this is the CLI: skip the step and say "Sidebar group skipped: not in the desktop app."

1. `list_groups`. A group named `<square> - <name>` exists → use it.
2. Else the square is the first of 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜ that no group name starts with. All taken → ask which one. `create_group` with name `<square> - <name>`.
3. `move_sessions` with `session_ids: ["self"]` and the group's id, unless `get_session` `self` shows it is already in it.
4. `change_directory` to `<repo>`, unless the session already runs there. It takes effect when the turn ends; keep using absolute paths.

**Done when:** this session is in the group and moving to `<repo>`, or the step is skipped with the reason said.

## 4. Specs

The project is empty when `<repo>` holds nothing but `.git`. Then offer: "Plan it now? Type `/to-spec` for a small project or `/wayfinder` for a big one, here in this session." Not empty → no offer.

**Done when:** the offer is made for an empty project, or it is not empty.

## 5. Brain wiki

`git -C "<vault>" remote get-url origin` fails → the vault is no brain: skip and say "Wiki skipped: `<vault>` is not a git repo with an origin."

Else ask once: "Add a brain wiki? (yes/no)". Yes → run `/wiki <name>`, which takes it from here and prints its own lines. No → "Wiki skipped: Quinn said no."

**Done when:** `/wiki` has run, or the step is skipped with the reason said.

## 6. Report

Print what was created, what was already there, and what was skipped or stopped and why, one line each: folder, repo, wiki repo, Project, sidebar group, brain wiki.

**Done when:** the report is printed.
