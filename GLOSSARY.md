# Skills

Quinn's personal Claude Code skills: the ticket flow (`/ticket`, `/work`, `/send`), the briefing, and the helpers around them.

## Language

**To-do**:
An open line in the vault's briefing notes, tagged with its project. Quinn writes one with `/note`, or `/send` writes one from a ticket's loose ends: at most one per ticket, and only a breaking or ticket-worthy one, as `/send` defines them.
_Avoid_: briefing note, project note, leftover

**Loose end**:
An open point a session reports when it stops: something still to check, decide or do that the session did not finish.
_Avoid_: leftover, open point

**Close**:
Ending a ticket without code, for example because it turned out already fixed or obsolete. The reason is recorded on the ticket.
_Avoid_: cancel, abandon, drop

**Script test**:
A check of one of a skill's scripts against fixed inputs, with no model involved.
_Avoid_: unit test, bash test

**Live test**:
A run of a whole skill through the model in a fixture vault and project, judged by the files, board and branches it leaves behind.
_Avoid_: end-to-end test, `claude -p` test
