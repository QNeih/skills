# skills

My Claude Code skills. Per ticket I type two commands, `/work` and `/send`;
everything in between runs on its own and stops only where I have to decide.

    /dashboard      full-screen, keyboard-driven: next tickets, ticket workflow, session tree
    /start-project  start the project's servers and containers, open it in the browser
    /ticket TEXT    add an issue to the project's GitHub board
    /work KEY       claim the ticket, pick a route (fix, grill, build, wayfinder), start it
    /build          spec → tickets → test-first build in subagents → review
    /send           commit, fix leftovers, rebase, lint, test, push, open the PR, move the board card

Built on Matt Pocock's skills (separate install): `/build` and `/work` hand off
to his `to-spec`, `to-tickets`, `implement-spec`, `implement`, `wayfinder`,
`grill-with-docs` and `diagnosing-bugs`.

## Workflow

Blue: a command I type. Yellow: a point where the flow stops for my decision.
Grey: Matt Pocock's skills. Everything else runs on its own.

```mermaid
flowchart TD
    dashboard(["/dashboard"]):::cmd --> dash["Per project: tickets in progress, next ticket,<br/>conflicting PRs, Sentry issues, Dependabot PRs, sessions"]
    dash --> key{"Key?"}:::gate
    key -- "s" --> sentryfix["sentry-fix<br/>one worktree per error"] --> draftpr["Draft PRs"]
    key -- "d" --> depreview["dependabot-review<br/>checks every open PR in parallel"]
    key -- "→ on a ticket:<br/>background session" --> ticket
    key -- "→ on an imported ticket:<br/>background session" --> send

    newticket(["/ticket TEXT"]):::cmd --> card["Issue in To do<br/>on the GitHub board"] --> ticket

    ticket(["/work KEY"]):::cmd --> claim["Claim on the board<br/>GitHub Project, Jira or other tracker"]
    claim --> branch["Cut branch from base"]
    branch --> import[".scratch/KEY-slug/ticket.md<br/>.handoffs/HANDOFF-KEY.md"]
    import --> route{"Route by<br/>ticket shape"}

    route -- "only the reporter can answer" --> needsinfo["needs-info:<br/>questions for the reporter"]:::gate
    route -- "bug, cause unclear" --> diagnose["diagnosing-bugs"]:::pocock
    route -- "clear, one session" --> implement["implement"]:::pocock
    route -- "open design questions" --> grill["grill-with-docs"]:::pocock
    route -- "multi-session" --> build
    route -- "too big or foggy" --> wayfinder["wayfinder<br/>one session per map ticket"]:::pocock

    grill --> implement
    wayfinder --> build

    subgraph build ["/build"]
        direction TB
        spec["to-spec"]:::pocock --> seams{"Seams OK?"}:::gate
        seams --> tickets["to-tickets"]:::pocock --> breakdown{"Breakdown OK?"}:::gate
        breakdown --> implspec["implement-spec<br/>test-first, one subagent<br/>per frontier ticket"]:::pocock
        implspec --> review["code-review<br/>standards + spec"]
    end

    diagnose --> fixreview["code-review<br/>standards + spec"]
    implement --> fixreview
    fixreview --> send
    review --> send

    send(["/send"]):::cmd --> commit["Commit by concern"] --> leftovers["Fix leftovers"] --> rebase["Rebase onto the base"] --> lint["npm run lint-fix"] --> test["test.sh or tests/run.sh"] --> push["Push"]
    push --> pr["Open or reuse PR;<br/>merge it where CLAUDE.md says so"] --> board["Move card:<br/>Jira → Code Review,<br/>GitHub → Done on merge"]
    send -- "nothing on the branch:<br/>close with a reason" --> board
    board --> cleanup["Stop the ticket's dev servers;<br/>delete branch, worktree,<br/>.scratch and .handoffs"]

    classDef cmd fill:#2563eb,stroke:#1e40af,color:#fff
    classDef gate fill:#facc15,stroke:#a16207,color:#000
    classDef pocock fill:#6b7280,stroke:#374151,color:#fff
```

## Skills

| | Skill | What it does | Uses |
| --- | --- | --- | --- |
| **Daily** | `dashboard` | Starts my full-screen local dashboard (each project's state, ticket workflow, background sessions) and brings its window to the front. The app lives in its own repo, `dashboard`, under the projects root. | dashboard repo |
| | `start-project` | Starts every entry of the project's run file (`.claude/launch.json`: dev servers, containers) detached and opens the first entry's port in the browser. Without a run file it suggests one from the compose file or package scripts. A port another folder holds moves to a free one. The dashboard's "e" key runs it. | repo |
| **Ticket flow** | `ticket` | Adds one issue to the project's GitHub board (a Project linked to the code repo; the id is the board's key and the issue number, `SKL-12`), in the language of the issues already there. First asks what the text leaves open that would change the work. Given only an id, points to `/work`. | GitHub |
| | `work` | Claims a ticket on the project's board (GitHub Project, Jira, or any tracker with a connector), cuts its branch, imports it, and starts the route that works on it. | board (GitHub, Jira, other), repo |
| | `build` | Runs a multi-session feature in one session: spec, tickets, test-first build in subagents, code review. | repo |
| | `send` | Ships the branch: commit, fix its own leftovers, rebase onto the base branch, lint, test, push, PR with the tracker link, board card moved, the ticket's dev servers stopped, branch and worktree cleaned up. Names the other open PRs that now conflict. A ticket branch with nothing on it is closed instead: card to Done with the reason, same cleanup. | GitHub, board, repo |
| **Maintenance** | `sentry-fix` | Fixes Sentry errors in their own worktrees and opens draft PRs; finds the Sentry projects from the DSNs in the code. | Sentry, GitHub |
| | `dependabot-review` | Checks every open Dependabot PR in parallel: does it break the build, could it change behaviour. | GitHub |
| **Setup and misc** | `new-project` | Sets up a project: folder and git, code repo, GitHub board, sidebar group. Creates only what's missing. | GitHub, repo |
| | `wiki` | Gives a project a wiki: a private repo of shared pages inside the brain, fed once a day from the project's notes. Schedules the wiki task and the daily brain sync. Creates only what's missing. | vault, GitHub |
| | `cv-update` | Weekly: checks my GitHub PRs and `/teach` lessons against my CV and asks before editing it. | GitHub |

## Install

    npx skills add mattpocock/skills   # required: the skills above hand off to these
    npx skills add QNeih/skills

These are written for my setup and meant to be read and adapted. They expect:
a GitHub Project per project, linked to its code repo, with the settings in the repo's `.claude/project.md` (Jira for projects that use it), an Obsidian vault (the brain, for `/wiki`), `gh`, the Jira MCP server and `acli` where a project uses Jira,
and the `sentry` CLI where it uses Sentry.
Put your projects root and vault path in `~/.claude/CLAUDE.md`.
