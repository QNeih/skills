---
name: briefing
description: "Whole-day briefing across every active project: what Quinn did last workday, what's next, Jira changes, new Sentry errors, new Dependabot PRs, mail and Teams waiting on Quinn, today's meetings, open notes. Use when Quinn types \"/briefing\", asks for the day's overview or asks where things stand, in the morning or back from a break or time off."
---

# Briefing

One briefing for the whole day, run from any folder. It shows only what is new or waits on Quinn; a source, line or project with nothing to show is left out silently.

The vault path and the projects root are set in `~/.claude/CLAUDE.md`.

## 1. Gather

Run, unsandboxed (it calls `acli`, `sentry` and `gh`):

```bash
VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/gather.sh
```

It prints header lines, then `# Today` and one `# <project>` section per project with something to show:

- Header: `today:`, `last workday:`, `since:` (start of the window for new items: the last `/briefing` run, or last workday 00:00 on the first run) and, on a later run the same day, `later run today: no Did`.
- `prompt <date time> <text>` and `commit <date time> <subject>`: Quinn's prompts and commits from last workday through yesterday. `left off: <branch>, clean|uncommitted (N files)`.
- `next: <ticket or card> (in progress|to do|top pick)`.
- `jira added: …` and `jira back: <key> <from> → <to> …`: changes in the open sprint since the last run.
- `sentry <org>/<project>[ staging]: N issues, new: <shortIds>, regressed: <shortIds>`.
- `dependabot: N new of M open: #<n> <title>; …`.
- `note <n>: <date> <text>`: open notes from `<vault>/Briefing notes.md`; under `# Today` when they name no active project.
- `skill <name>: added|removed|updated` and `plugin <name>: added|removed|<old> → <new>`, under `# Today`: installed third-party skills and plugins that changed since the last run, read from the hourly backup in `<projects root>/claude-config`.
- `error: <source>: <problem> — <fix>`: a configured source that failed.

`gather.sh` keeps its state in `~/.claude/briefing/` (last-run time, Jira snapshots) and updates it on every run. An `error: vault …` line alone → show it and stop.

**Done when:** the gather output is in hand.

## 2. Messages and meetings

Mail, Teams and calendar come from the Microsoft 365 connector, in a subagent so its tool output stays out of this context. Call the Agent tool (`general-purpose`) with this prompt, filled in:

```
Read ${CLAUDE_SKILL_DIR}/messages.md and follow it.
<the today:, last workday: and since: lines from step 1>
vault: <vault>
projects root: <projects root>
gather.sh: ${CLAUDE_SKILL_DIR}/gather.sh
state dir: ~/.claude/briefing
```

It returns final lines only:

- `today: <line>`: a meeting or a message for **Today**; `today: +N more` closes the unmatched messages.
- `<project>: <line>`: a `Mail`/`Teams` message for that project.
- `unmatched: <entry> (<n>×) → <project>?`: a sender or chat offered for that project's `contacts`.
- `error: <source>: <problem> — <fix>`.

No lines → no messages or meetings today; carry on.

**Done when:** the subagent's lines are in hand.

## 3. Brief

Write the brief from the lines of steps 1 and 2; every fact comes from them, the brief only condenses.

```
## Monday, 9 Nov — last workday Fri, 6 Nov

**Today**
- 10:00–10:30 Weekly sync [Acme]
- Mail · ann@other.test · Fri 16:10: asks for the offer draft
- Note 1: call the tax office

**Acme**
- Did: <2–4 bullets>; left off: feature/ACM-12, clean
- Next: ACM-12 Export grounding
- Jira: added ACM-40 New thing — Max · back: ACM-31 Review → In Progress
- Sentry staging: 3 issues, new: ACME-4F2 · regressed: ACME-3A1
- Dependabot: 2 new — Bump left-pad, Bump zod
- Teams · max@acme.test · Fri 11:02: wants a date for the release
- Note 2: send the offer
- Sentry: sentry api projects/ failed: not authenticated — sentry auth login

Unmatched: tom@beta.test (2×) → Beta?
Reply: "fix all" (Sentry) · "/dependabot-review" · "add all" · "done 2"
```

- **Today** first: meetings, then messages (`+N more` last), then notes, then one `Packages:` line listing the `skill`/`plugin` lines, then errors. For an updated skill, add what changed in a few words, read from `git -C <projects root>/claude-config log -p --since=<since> -- agents/skills/<name>`. Then one section per `#` project section of the gather output, in its order; a project with only step 2 lines gets a section after them.
- In a project section: Did, Next, Jira, Sentry, Dependabot, messages, notes, errors.
- **Did**: 2–4 bullets condensed from the `prompt` and `commit` lines, grouped by ticket or topic, then the `left off` value. No `prompt`/`commit` lines (or `later run today`) → no Did line.
- **Next**: every `next:` line, key and title.
- **Sentry**: one line per `sentry` line; name the Sentry project when the section has several.
- Every `jira`, `sentry`, `dependabot`, `note` and `error` line and every step 2 line appears; step 2 lines verbatim without their `today:`/`<project>:` prefix, `unmatched:` lines as `Unmatched: …` after the last section. Notes keep their number, so `done <n>` hits the right one. Errors keep their fix verbatim.
- **Reply** line: only the offers that apply: `"fix all"` when a `sentry` line has new or regressed ids, `"/dependabot-review"` when a `dependabot` line exists, `"add all"` when `Unmatched:` lines are shown, `"done <n>"` when notes are shown.

Then stop and wait.

**Done when:** the brief is shown and every line from steps 1 and 2 is in it.

## 4. Replies

- **"fix all"** → for every project with a `sentry` line, all its new and regressed short ids. **Short ids** → the project whose `sentry` line lists them. Per project, one after another, call the Skill tool with `sentry-fix` and args `<shortIds> <project name>`; it finds that project's folder and makes its own worktrees.
- **`done <n> …`** → run `VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/gather.sh --done <n> …` with the numbers as the brief showed them, and show the ticked lines. An `error:` line → show it.
- **`add all`** → every `Unmatched:` line; **names** (an entry or a project from those lines) → only the lines they name. Per line run `VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/gather.sh --add-contact <project> <entry>` and show its output. No reply → nothing is added; never add an entry Quinn didn't confirm.
- **`/dependabot-review`** → it runs in the project's folder; name the folder(s) with new Dependabot PRs (`VAULT=<vault> PROJECTS_ROOT=<projects root> bash ${CLAUDE_SKILL_DIR}/project.sh --note <project>` prints `dir:`).

**Done when:** each reply's action ran and its result is shown.
