# Setup

The steps for a person who cloned this wiki and says "set up". They connect the wiki to that person's notes on this machine: which folder holds the notes, and a daily wiki task that ingests them. Each step checks first and does only what is missing, so a second "set up" is safe.

`<wiki>` is this file's folder as an absolute path.

## 1. Folders

`<wiki>/.local` exists → read `brain:` and `notes:` from it and go to step 2.

Else the setup needs two existing folders. Take them from the request when it names them. Otherwise ask, one question per message:

1. "Where is your brain folder, the one that holds all your notes?"
2. "Which folder inside it holds your notes on this project?"

These are the setup's only questions about the notes: the brain keeps the structure it has, and the setup works with folders that exist. Everything in the notes folder becomes a source for the team's wiki, so it has to be a folder inside the brain folder, not the brain folder itself. A path that is not an existing folder, or a notes folder that is not inside the brain folder → say which and ask again.

Write `<wiki>/.local` with both as absolute paths:

```
brain: /Users/mara/notes
notes: /Users/mara/notes/customers/acme
```

`.local` is per person, so git ignores it. `git -C "<wiki>" check-ignore -q .local` fails → add the line `.local` to `<wiki>/.gitignore`.

**Done when:** `.local` names two existing folders, the notes folder inside the brain folder, and git ignores `.local`.

## 2. Place

`<wiki>` is `<notes>/wiki` → nothing to do.

Else offer: "Move this wiki to `<notes>/wiki`, so its pages sit next to your notes? (yes/no)"

- Yes and `<notes>/wiki` is free → `mv "<wiki>" "<notes>/wiki"`. `<wiki>` is the new path from here on; say that Claude is opened there from now on.
- Yes and `<notes>/wiki` is taken → say so and leave the wiki where it is.
- No → leave it.

`<wiki>` now lies inside the brain folder and `git -C "<brain>" check-ignore -q "<wiki>"` fails while the brain is a git repo → add one line to the report: "Your brain is a git repo: add `<wiki>` to its ignore list, the wiki is its own repo."

**Done when:** the wiki is at `<notes>/wiki`, or the person's no or the taken folder is noted.

## 3. Wiki task

The wiki task is a daily local scheduled task that follows `INGEST.md`. Only a local scheduled task fits, since it runs on this machine, where the notes are.

`<task>` is `wiki-` plus the notes folder's name in kebab case (`wiki-acme-proto`).

- `~/.claude/scheduled-tasks/<task>/SKILL.md` exists → already scheduled; leave it.
- Else load the scheduled-task tools with ToolSearch (query `scheduled task`) and create a local scheduled task with the one that does that:
  - name: `<task>`
  - description: `Ingest my new sources into the wiki at <wiki>`
  - schedule: daily at 16:00
  - prompt: `Follow <wiki>/INGEST.md.`
- No tool that creates a local scheduled task → this session cannot schedule. Say: "Wiki task not scheduled: this session has no scheduled-task tool. Open `<wiki>` in the Claude desktop app and say "set up" again."

The tool writes the task; `~/.claude/scheduled-tasks` is its folder to write.

**Done when:** the task exists, or the sentence is said.

## 4. Report

One line each: the two folders, where the wiki is, and the wiki task (scheduled, already there, or not scheduled and why). Then: "The first run ingests every source in `<notes>` that the source log lacks. Say "ingest" to run it now."

**Done when:** the report is printed.
