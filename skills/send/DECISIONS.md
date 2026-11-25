# Decisions in `ticket.md`

How `/send` settles a ticket's `## Decisions` section before it copies the section into the brain.

## Decision line

```
- <what>. Why: <reason>. Rejected: <option and its reason>.
```

- One decision is one line. Every non-blank line of the section is read as a decision line, so a decision that needs more words stays on its line, without a wrapped second line or a sub-bullet.
- `Rejected: none` when no alternative was considered.
- The whole section is the single word `none` when the work held no choice.

## Sources

A `Why:` and a `Rejected:` are copied in meaning from a **source**: this session (the conversation and its sub-agents' reports), the handoff, or `ticket.md` itself. The diff (with git, `git diff origin/<base>` plus the untracked files, `<base>` being `ticket.md`'s `base:`) shows what was chosen, never why.

A reason or a rejected option that no source gives → stop and ask Quinn in plain text: list those decisions, and ask for the reason and the rejected option of each. Write the lines from the answer.

## Fill an empty section

The check printed `decisions: empty`: the section is missing, blank, or holds only the template placeholder. Only `/grill-with-docs` fills it, so a ticket routed straight to `/implement` arrives empty.

1. List the **choices** the work made: each point where another option was open (an approach, a format, a default, a dependency, a scope cut). Read the sources and the diff.
2. No choice (a mechanical change, or nothing on the branch) → write `none` into the section; a missing section goes after `## Summary`.
3. Else write one decision line per choice, each label from a source (above). A session started fresh for the send has only the diff, so it asks Quinn.

Keep the lines written, or that it was `none`, for the report.

## Repair a refused line

The script printed `error: decision line without <label> in <ticket.md>: <line>`. Rewrite that line in `ticket.md` as one decision line: join a wrapped line or a sub-bullet into the decision it belongs to, and take a missing label's content from a source (above). Rerun the script; it names one refused line per run. Keep each rewritten line for the report.
