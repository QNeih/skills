---
name: wiki
description: Give a project a wiki — a private repo of shared knowledge inside the brain — and schedule the daily tasks that feed it, creating only what's missing.
argument-hint: "<project> [repo name]"
disable-model-invocation: true
---

# Wiki

`/wiki <project> [repo name]` gives a project a wiki: its own private GitHub repo, cloned inside the brain at `wiki/projects/<Name>`, fed once a day from the project's sources in `raw/<Name>`. Every step checks first and creates only what's missing, so a re-run on a project that has a wiki changes nothing.

The brain is the vault. Its path and the projects root are set in `~/.claude/CLAUDE.md` (a project `CLAUDE.md` may replace them).

Keep a list of what you created, what was already there and what you skipped; step 6 prints it.

## 1. Project

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/vault-lookup.sh --note "<project>"
```

Try the whole argument as `<project>` first. `project: none` and the argument has several words → the last word is the repo name and the rest is `<project>`; run it again. Still `project: none` → say its `reason:` and stop.

Only the `project:` line counts; a wiki needs no checkout, so `dir: none` is fine.

- `<name>`: the `project:` line.
- `<repo>`: the repo name from the argument, else `<name>-wiki` with spaces as hyphens.
- `<wiki>`: `<vault>/wiki/projects/<name>`.

**Done when:** `<name>`, `<repo>` and `<wiki>` are set, or you stopped with the reason.

## 2. Wiki

`git -C "<wiki>" remote get-url origin` prints a URL → the wiki is there with its remote; go to step 3.

Else look for the repo on GitHub, so a wiki that already lives there is cloned instead of started a second time:

```bash
gh repo view "<repo>" --json url,sshUrl
```

- It prints JSON → `<remote>` is `sshUrl` when `gh config get git_protocol` prints `ssh`, else `url`.
- It fails with `Could not resolve to a Repository` → no `<remote>`.
- Any other failure → say `gh`'s message and stop.

Then run the create script, with `<remote>` only when there is one:

```bash
bash ${CLAUDE_SKILL_DIR}/wiki.sh "<vault>" "<name>" [<remote>]
```

It prints `created:`, `cloned:` or `exists:` with the folder, and adds the wiki ignore line to the brain when missing.

**Done when:** `<wiki>` is a git repo and the script's line is on your list.

## 3. GitHub repo

`git -C "<wiki>" ls-remote origin main` prints a line → the wiki is on GitHub; nothing to do.

Else something has to go out, so ask first, once: "Create the private GitHub repo `<repo>` on your account and push the wiki? (yes/no)". When the repo exists and only the push is missing, ask "Push the wiki to `<remote>`? (yes/no)".

- **Yes**, no `<remote>` and no origin → `gh repo create "<repo>" --private --source "<wiki>" --remote origin --push`.
- **Yes**, otherwise → `git -C "<wiki>" remote add origin <remote>` when origin is missing, then `git -C "<wiki>" push -u origin main`.
- **No** → "GitHub repo skipped: Quinn said no. The wiki stays local."

A command that fails → could not fix, with its message as the cause; go on with step 4.

**Done when:** `ls-remote origin main` prints a line, or the skip or the cause is on your list.

## 4. Wiki task

The wiki carries its own setup steps. Follow `<wiki>/setup-prompt.md` with these answers in place of its questions:

- brain folder: `<vault>`
- project-notes folder: `<vault>/raw/<name>`, created when missing
- step 2 (Place): leave the wiki where it is, without asking

It records the folders and schedules the daily wiki task, or says why it could not.

**Done when:** `setup-prompt.md`'s report lines are on your list.

## 5. Brain sync task

One per brain: a daily local scheduled task that commits and pushes the brain by running one script.

- `~/.claude/scheduled-tasks/brain-sync/SKILL.md` exists → already scheduled; leave it.
- `git -C "<vault>" remote get-url origin` fails → skip: "Brain sync task skipped: `<vault>` is not a git repo with an origin."
- Else load the scheduled-task tools with ToolSearch (query `scheduled task`) and create a local scheduled task with the one that does that:
  - name: `brain-sync`
  - description: `Commit and push the brain once a day`
  - schedule: daily at 17:00
  - prompt: ``Run `bash ${CLAUDE_SKILL_DIR}/brain-sync.sh "<vault>"` and report its output in one line, then end the session.`` with both paths written out as absolute paths.
- No tool that creates a local scheduled task → this session cannot schedule. Say: "Brain sync task not scheduled: this session has no scheduled-task tool. Run `/wiki <project>` again in the Claude desktop app."

Only a local scheduled task fits, since it runs on this machine, where the brain is. The tool writes the task; `~/.claude/scheduled-tasks` is its folder to write.

**Done when:** the task exists, or the skip or the sentence is on your list.

## 6. Report

One line each, with what was created, what was already there, and what was skipped or could not be fixed and why: wiki (with its folder), GitHub repo, wiki task, brain sync task.

**Done when:** the report is printed.
