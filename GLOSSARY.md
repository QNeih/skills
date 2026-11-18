# Skills

Quinn's personal Claude Code skills: the ticket flow (`/ticket`, `/work`, `/send`), the briefing, and the helpers around them.

## Language

**To-do**:
An open line in the vault's briefing notes, tagged with its project. Quinn writes one with `/note`.
_Avoid_: briefing note, project note

**Leftover**:
Something still wrong or unfinished on a ticket's branch before its PR opens. The session fixes it when the ticket's change caused it, or when a build, a test or data breaks.
_Avoid_: loose end, open point

**Could not fix**:
Something a session could not fix or do, always reported with its cause. It is a report line, never a to-do.
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
