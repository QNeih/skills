# skills

My Claude Code skills. Per ticket I type two commands, `/ticket` and `/send`;
everything in between runs on its own and stops only where I have to decide.

    /briefing     what's new or waiting on me, across all projects
    /ticket KEY   claim the ticket, pick a route (fix, grill, build, wayfinder), start it
    /build        spec → tickets → test-first build in subagents → review
    /send         lint, commit, push, open the PR, move the board card

Built on Matt Pocock's skills (separate install): `/build` and `/ticket` hand off
to his `to-spec`, `to-tickets`, `implement-spec`, `implement`, `wayfinder`,
`grill-with-docs` and `diagnosing-bugs`.

## Skills

| | Skill | What it does |
| --- | --- | --- |
| **Daily** | `briefing` | One whole-day briefing across every project: what I did last workday, what's next, Jira changes, new Sentry errors and Dependabot PRs, mail and Teams messages waiting on me, today's meetings. |
| | `note` | Saves a to-do for the briefing, tagged with the project I'm in. |
| **Ticket flow** | `ticket` | Claims a ticket on the project's board (Jira, an Obsidian Kanban board, or any tracker with a connector), cuts its branch, imports it, and starts the route that works on it. |
| | `build` | Runs a multi-session feature in one session: spec, tickets, test-first build in subagents, code review. |
| | `send` | Ships the branch: lint, commit, push, PR with the tracker link, board card moved, branch cleaned up. |
| **Maintenance** | `sentry-fix` | Fixes Sentry errors in their own worktrees and opens draft PRs; finds the Sentry projects from the DSNs in the code. |
| | `dependabot-review` | Checks every open Dependabot PR in parallel: does it break the build, could it change behaviour. |
| **Setup and misc** | `new-project` | Sets up a project: folder and git, project note, board, sidebar group, Fork workspace. Creates only what's missing. |
| | `add-context` | Files an interview, transcript or meeting notes into a project's `context/` folder by its `INDEX.md`, merges it to main, and tells the running sessions what changed. |
| | `ask` | Answers questions about the codebase without changing files. |
| | `cv-update` | After `/send`, decides whether the work belongs on my CV and asks before editing it. |

## Install

    npx skills add mattpocock/skills   # required: the skills above hand off to these
    npx skills add QuinnNei/skills

These are written for my setup and meant to be read and adapted. They expect:
an Obsidian vault with one note per project, the Microsoft 365 connector
(`/briefing`), `gh`, the Jira MCP server and `acli` where a project uses Jira,
and the `sentry` CLI where it uses Sentry.
Put your projects root and vault path in `~/.claude/CLAUDE.md`.

## Extras

- **session-nav** (Claude desktop app only): a bar above the prompt that links
  back to the parent session and to child sessions. It also carries the
  `cv-update` hook, which runs `cv-update` after `/send` and `/teach`.
  `/plugin marketplace add QuinnNei/skills`, then `/plugin install session-nav@quinn`.
- **break-reminder**: opens a small window every hour that reminds me to drink
  water and stretch; `/break` opens it right away.
  `/plugin install break-reminder@quinn`.
