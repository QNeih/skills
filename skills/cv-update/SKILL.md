---
name: cv-update
description: Decide whether the work just finished (a /send or /teach run) belongs on Quinn's CV, and tell Quinn in one sentence whether an update is needed and why; edits only after Quinn approves. Triggered by the session-nav plugin's hook after /send and /teach; also run via /cv-update or "update my CV".
---

# CV update check

**CV**: `cv/quinn_neihaus_cv.md` under the projects root named in `~/.claude/CLAUDE.md`. No projects root there, or no CV at that path → say which and stop.

## 1. Read the CV

**Done when:** you have read the whole CV.

## 2. Decide

Compare what this session shipped (`/send`: the commits and PR) or learned (`/teach`: the lesson topic and learning records) against the CV. Update only if one of these is true:

- A technology, tool or skill is now used for real and is not on the CV yet (or moved from "Exploring" to working knowledge).
- A concrete, notable achievement: a measurable result, a feature or module now owned, a migration or architecture decision led.
- A fact on the CV is now wrong (role, dates, numbers).

Routine bug fixes, small tickets, refactors and a single beginner lesson are **not** enough. When in doubt, don't update.

**Done when:** you have a verdict: no update, or one proposed change.

## 3. Tell Quinn

Never edit on your own. Every run ends with exactly one sentence to Quinn giving the verdict and the reason:

- **No update** → "No CV update needed: <why>." e.g. "No CV update needed: this was a routine bug fix in an area the CV already covers." Then stop.
- **Update suggested** → "CV update suggested: <the change> because <why>." Show the proposed line as a one-line diff, then ask with AskUserQuestion: apply / skip.

**Done when:** Quinn has the sentence, and for a suggestion, has answered apply or skip. Skip → stop.

## 4. Update (only after Quinn says apply)

- Edit the smallest part that fits: one bullet, one skill entry, one number. Keep the CV's tone, tense and length; never add a section.
- Facts only from this session or from Quinn. Don't invent numbers.
- In the CV folder: `python3 build.py` (regenerates the PDF from the Markdown; never edit the PDF), then `git commit -am "<what changed>"` and `git push`. Any of these fails → say which and stop.

**Done when:** the change is committed and pushed, or Quinn knows which step failed.
