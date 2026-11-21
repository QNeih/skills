---
name: new-project
description: Set up a new or existing project — folder, code repo, board (GitHub, or the code host's tracker), sidebar group, optional brain wiki — creating only what's missing.
argument-hint: "[name | clone URL], or nothing for the current folder"
disable-model-invocation: true
---

# New project

`/new-project [name|clone URL]` makes a project ready in one go. Every step checks first and creates only what's missing, so a re-run on an existing project is safe.

A project `x` is one private code repo. Its checkout is `<projects root>/x` (flat) or `<projects root>/x/x` (nested: a project folder of the same name around it); a new project is flat. Its board is a GitHub Project linked to that repo (the tracker of the code's host when that is not GitHub), and its settings file is `.claude/project.md` in the checkout. The projects root is set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace it). The lookup prints the project's lines:

```bash
cd <folder> && PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh [--name <name>]
```

Keep a list of what you created and what was already there; step 6 prints it.

## 1. Folder and repo

`<repo>` is the checkout and `<name>` its folder's name.

- **Empty** → the current folder: `<repo>` is the lookup's `dir:` line run from here (the main checkout, also from a worktree).
- **Clone URL** (`https://…`, `git@…`, `ssh://…`) → `<name>` is the last path part without `.git`. The lookup with `--name <name>` prints a `dir:` line → `<repo>` is that folder, untouched. Else `<repo>` is `<projects root>/<name>`: `git clone <url> "<repo>"`.
- **Name** → the lookup with `--name <name>` prints a `dir:` line → `<repo>` is that folder, untouched. Else `<repo>` is `<projects root>/<name>`: `mkdir -p "<repo>"`.

Then make what `<repo>` lacks:

- No git (`git -C "<repo>" rev-parse` fails) → `git -C "<repo>" init`.
- No origin (`git -C "<repo>" remote get-url origin` fails) → ask once "Owner for the new repo? (a GitHub user or org)", then `gh repo create <owner>/<name> --private --source "<repo>" --remote origin`.

`<repo>` is its absolute path with symlinks resolved (`cd <repo> && pwd -P`) from here on.

**Done when:** `git -C "<repo>" remote get-url origin` prints a URL: the one `<repo>` already had, or the new GitHub repo.

## 2. Board

Run the lookup from `<repo>` and follow `${CLAUDE_SKILL_DIR}/BOARD.md`, with one change: in place of its board question, the code host picks the answer. A board the lookup already names (GitHub with a `number:`, Jira, a link or text) stays as it is.

- The origin's host contains `github` (`github.com`, an SSH alias like `github.com-work`, GitHub Enterprise) → the answer is `github`: `board.sh create` makes the board, then the key question.
- Origin on another host (e.g. Azure DevOps) → ask once: "Where are the tasks for <project> managed? Paste the link of its tracker." The link is the answer.

**Done when:** the lookup prints `project: <name>` with a `board:` other than `none`, and for `github` also `number:` and `repo:`.

## 3. Sidebar group

Needs the desktop tools `create_group`, `move_sessions` and `change_directory` (load them with ToolSearch). Not available → this is the CLI: skip the step and say "Sidebar group skipped: not in the desktop app."

1. `list_groups`. A group named `<square> - <name>` exists → use it.
2. Else the square is the first of 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜ that no group name starts with. All taken → ask which one. `create_group` with name `<square> - <name>`.
3. `move_sessions` with `session_ids: ["self"]` and the group's id, unless `get_session` `self` shows it is already in it.
4. `change_directory` to `<repo>`, unless the session already runs there. It takes effect when the turn ends; keep using absolute paths.

**Done when:** this session is in the group and moving to `<repo>`, or the step is skipped with the reason said.

## 4. Specs

The project is empty when `<repo>` holds nothing but `.git` and `.claude/`. Then offer: "Plan it now? Type `/to-spec` for a small project or `/wayfinder` for a big one, here in this session." Not empty → no offer.

**Done when:** the offer is made for an empty project, or it is not empty.

## 5. Brain wiki

`git -C "<vault>" remote get-url origin` fails → the vault is no brain: skip and say "Wiki skipped: `<vault>` is not a git repo with an origin."

Else ask once: "Add a brain wiki? (yes/no)". Yes → run `/wiki <name>`, which takes it from here and prints its own lines. No → "Wiki skipped: Quinn said no."

**Done when:** `/wiki` has run, or the step is skipped with the reason said.

## 6. Report

Print what was created, what was already there, and what was skipped or stopped and why, one line each: folder, code repo, board, settings file, sidebar group, brain wiki.

**Done when:** the report is printed.
