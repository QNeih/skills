---
name: ticket
description: Add one ticket to the project's board (GitHub issue, or Jira issue), written in the board's own conventions.
argument-hint: "<what the ticket is about>"
disable-model-invocation: true
---

# Ticket

`/ticket <text>` creates one ticket on the project's board, shaped like the tickets already there, so `/work` can pick it up. On GitHub the ticket is an issue in the project's wiki repo, added to the Project in `Todo`; its number is its id.

## 0. Arguments

- Only a ticket id (`KEY-12`, `12`, `#12` or `AB#1234`, nothing else) → stop: "/ticket creates a ticket. To start <id>, run `/work <id>`."
- Empty → ask "What is the ticket about?" and stop.

## 1. Project and board

```bash
bash ${CLAUDE_SKILL_DIR}/project.sh
```

- `project: none` → stop and print its `reason:`.
- `board: github` → GitHub; every board call goes through `bash ${CLAUDE_SKILL_DIR}/tickets.sh` (`list`, `show <n>`, `create`).
- `board: jira` → Jira through the claude.ai Atlassian MCP server, project `key:` from the lookup. Its tools are missing or unauthenticated → stop and ask Quinn to run `/mcp` → "claude.ai Atlassian".
- Any other value → stop: "/ticket writes GitHub and Jira boards only; <project>'s board is <board>."

**Done when:** the board is GitHub or Jira.

## 2. Conventions

Read the board's own tickets:

- GitHub: `tickets.sh list` for the open unblocked tickets; `tickets.sh show <n>` for the five newest, to read bodies and labels.
- Jira: `searchJiraIssuesUsingJql` with `project = <key> ORDER BY created DESC`, five results.

From those, newest weighted most, take:

- **Language** of titles and bodies (e.g. German on BGH).
- **Title style**: length, verb or noun phrase.
- **Body pattern**: the lines most bodies carry, in their order, with the labels and separators each uses (a description line, `Goal: …`, acceptance points).
- **Labels** the board uses.

No tickets yet → English, one description line, no labels.

**Done when:** you can name the language, the body pattern and the labels, each read off actual tickets.

## 3. Grill open questions

Find the **open questions**: what the text leaves open whose answer would change the work, such as which parts of the project it covers, which tool to use, or where it runs. Example: "add linter to project" leaves open which folders the linter checks, which linter, and whether it runs in `test.sh` or before `/send`. Ask only what the ticket's session could not settle while working.

Also compare the text with the tickets read in step 2: an overlap is an open question.

- No open questions → go on to step 4.
- Else → grill Quinn: one question per message, each with your recommended answer; wait for each answer.

Quinn's answers refine the text into the ticket text for step 4.

**Done when:** every open question is answered.

## 4. Draft

Write the title and body from the ticket text, in the board's language and body pattern.

- Quinn's text is a rough dictation. Rewrite it as clean board text: correct spelling and grammar, drop filler and repeats, spell out shorthand ("fx" → "for example"; keep command, tool and product names), split run-on thoughts into the pattern's lines, and turn questions into what is to be found out ("Find out why /send fails from the app"). Keep every point and its meaning; add none.
- Fill a pattern line only from what the ticket text (with Quinn's answers) says; drop the lines it gives nothing for, and report each dropped line as could not fix, with the cause "no source in the text". Effort, priority, offer item and benefit values come from Quinn, verbatim.
- **Needs**: the ids the text names, each checked to exist (`tickets.sh show <n>` on GitHub, `getJiraIssue` on Jira); text names none → no blockers. An id that does not exist → ask Quinn.
- **Labels**: `bug` only when the ticket is mainly a defect to fix; `urgent` when the text says urgent; `hotfix` when it says hotfix. `/work` cuts a `bugfix/` or `hotfix/` branch from `bug` and `hotfix`, so a feature that also fixes something gets neither. No other labels.

**Done when:** every point of the ticket text is in clean wording, every body line traces to the text, and every pattern line without a source is reported as could not fix.

## 5. Create

- GitHub:

  ```bash
  bash ${CLAUDE_SKILL_DIR}/tickets.sh create --title "<title>" --body "<body>" --label "<a,b>" --blocked-by "<n,n>"
  ```

  Leave out `--label` and `--blocked-by` when empty. It prints the issue number: the ticket id `#<n>`. A ticket with Needs shows as blocked on the board, and `/work` skips it until its blockers close.
- Jira: `createJiraIssue` in project `<key>` (type `Bug` for a bug, else `Task`; summary, description, labels). Then one `createIssueLink` of type `Blocks` per Needs id, the Needs ticket as the blocker. The issue key is the ticket id.

Print the id, the title and body, the labels, the blockers, and what it could not fix, and why.

**Done when:** the ticket exists on the board, its id is printed, and the ticket and what it could not fix are printed.
