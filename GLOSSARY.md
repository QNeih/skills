# Skills

Quinn's personal Claude Code skills: the ticket flow (`/ticket`, `/work`, `/send`), the dashboard, and the helpers around them.

## Language

**Board**:
A project's ticket list: a GitHub Project linked to the project's code repo, where a ticket is an issue in that repo. Construct uses Jira instead.
_Avoid_: vault board, Kanban file, wiki board

**Key**:
The short capital-letter name of a board, in its Project's title (`skills (SKL)`) and in front of every ticket id (`SKL-12` is issue 12). A board without one uses the bare issue number.
_Avoid_: prefix, project code

**Settings file**:
`.claude/project.md` in a project's main checkout. Its front matter names the board, the Project's number and owner, the key, and per-project choices such as the Sentry projects.
_Avoid_: project note, wiki settings, config

**Leftover**:
Something still wrong or unfinished on a ticket's branch before its PR opens. The session fixes it when the ticket's change caused it, or when a build, a test or data breaks.
_Avoid_: loose end, open point

**Could not fix**:
Something a session could not fix or do, always reported with its cause as a line of the session's report.
_Avoid_: still open, known issue

**Close**:
Ending a ticket without code, for example because it turned out already fixed or obsolete. The reason is recorded on the ticket.
_Avoid_: cancel, abandon, drop

**Script test**:
A check of one of a skill's scripts against fixed inputs, with no model involved.
_Avoid_: unit test, bash test

**Live test**:
A run of a whole skill through the model in a fixture vault and project, judged by the files, board and branches it leaves behind.
_Avoid_: end-to-end test, `claude -p` test

**Brain**:
One person's private Obsidian vault across all projects, kept as a git repo and pushed to GitHub once a day.
_Avoid_: second brain, knowledge base

**Wiki**:
One project's shared knowledge: Markdown pages in a private repo of their own, cloned inside each team member's brain. Optional, and pages only: the board and the settings live in the code repo.
_Avoid_: docs, knowledge base, GitHub wiki

**Source log**:
The file in a wiki that lists every source worked into its pages, one line each. A source is a note or file a person dropped into the project's folder in their brain.
_Avoid_: ingest log, history

**Decision note**:
A source in the brain that holds one ticket's decisions with their reasons and rejected options, plus the ADRs and glossary entries the ticket added or changed. Written when the ticket ships or closes, so the brain and the project's wiki learn why, not what.
_Avoid_: decision log, raw note

**Wiki template**:
The files every wiki starts with: its rules, its setup and ingest steps, an empty source log and an index.
_Avoid_: scaffold, boilerplate
