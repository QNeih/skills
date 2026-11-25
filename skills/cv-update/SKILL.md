---
name: cv-update
description: Review of Quinn's GitHub activity against the CV; proposes changes and edits only after Quinn approves. Runs as a daily scheduled task; also run via /cv-update or "update my CV".
---

# CV review

**CV**: `cv/quinn_neihaus_cv.md` under the projects root named in `~/.claude/CLAUDE.md`. No projects root there, or no CV at that path → say which and stop.

**Window**: the range the caller names (the daily task names its own); the last 7 days when none is named.

## 1. Gather the window

- **GitHub**: `gh search prs --author=@me --updated=">=<start date>" --limit 100 --json repository,title,state,url,body`. Covers every repo Quinn can see, client and private ones included. Open a PR's diff only when its title and body leave unclear what was built.

`gh` fails → say so and stop. No PRs → "No CV update needed: nothing shipped in the window." and stop.

**Done when:** you have the window's PRs.

## 2. Read the CV

**Done when:** you have read the whole CV.

## 3. Decide

Compare the window as a whole against the CV. Several small PRs in one area can add up to something worth listing; one routine PR can't. Propose a change only if one of these is true:

- A technology, tool or skill is now used for real and is not on the CV yet (or moved from "Exploring" to working knowledge).
- A concrete, notable achievement: a measurable result, a feature or module now owned, a migration or architecture decision led.
- A fact on the CV is now wrong (role, dates, numbers).

Routine bug fixes, small tickets and refactors are **not** enough. When in doubt, don't propose. Never put client ticket keys or client-internal details on the CV.

**Done when:** you have a verdict: no update, or at most three proposed changes.

## 4. Tell Quinn

Never edit on your own.

- **No update** → one sentence: "No CV update needed: <why>." Then stop.
- **Updates suggested** → for each: one sentence "<the change> because <why>", the PRs it rests on, and the proposed line as a one-line diff. Then end with the questions in plain text, numbered like the changes, each answerable with apply or skip. A scheduled run has no question dialog; Quinn answers in the run's session, and step 5 runs on that reply.

**Done when:** Quinn has the verdict, and for suggestions, has answered each one. All skipped → stop.

## 5. Update (only the changes Quinn applied)

- Edit the smallest part that fits: one bullet, one skill entry, one number. Keep the CV's tone, tense and length; never add a section.
- Facts only from the PRs or Quinn. Don't invent numbers.
- In the CV folder: `python3 build.py` (regenerates the PDF from the Markdown; never edit the PDF), then `git commit -am "<what changed>"` and `git push`. Any of these fails → say which and stop.

**Done when:** the changes are committed and pushed, or Quinn knows which step failed.
