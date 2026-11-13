---
name: build
description: Build a multi-session feature end to end in this session — spec, tickets, test-first build in subagents, code review — on the current ticket branch. Use after a wayfinder map, for a spec or a ticket too big for one session, when /work routes to /build, or to resume a stopped build.
argument-hint: "[spec, map or ticket path, or an idea]"
---

# Build

`/build` runs Matt Pocock's `to-spec` → `to-tickets` → `implement-spec` in this session and ends on the integration branch, ready for `/send`. **Load** a Pocock skill = read `~/.claude/skills/<name>/SKILL.md` and follow it (they set `disable-model-invocation`, so the Skill tool can't start them). Not installed → stop and name `npx skills add mattpocock/skills`.

The only gates are the ones inside those skills: to-spec's seam check and to-tickets' breakdown approval. Approving the breakdown starts the build; go straight on.

## Terms

- **Main checkout**: `dir` = parent of `git rev-parse --path-format=absolute --git-common-dir`. `.scratch/` lives there, also when you run from a worktree. Pass subagents absolute paths into it.
- **Feature folder**: `<dir>/.scratch/<feature>/`. `/work` already made `.scratch/<id>-<slug>/` with `ticket.md` for the current branch → that folder. Else a short kebab-case slug from the input.
- **Tracker**: local markdown in the feature folder, whatever the project's docs name as tracker. Spec at `spec.md`, tickets at `issues/<NN>-<slug>.md` with `**Blocked by:**` and `**Status:**` lines, labels as Pocock writes them (`ready-for-agent`, …). The vault board or Jira only holds the parent ticket; leave it alone.
- **Integration branch**: the branch checked out when `/build` starts (`/work`'s `feature/<KEY>`). On `main`, `develop` or a detached HEAD → create `feature/<feature>` from HEAD and say so.
- **Done ticket**: its `**Status:**` line reads `done`.
- **Frontier**: tickets that aren't done and whose every `Blocked by` ticket is done; lowest number first.

## 1. Resume or start

Find the feature folder.

- `issues/` holds tickets → resume: skip to step 4.
- Else the input (argument, or the conversation) is already a spec, i.e. it has `## Problem Statement` and `## Implementation Decisions` → write it to `spec.md` if it lives elsewhere; skip to step 3.
- Else (a wayfinder map, a ticket, an idea) → read it and continue with step 2.

**Done when:** the feature folder, the integration branch and the next step are named in one line to Quinn.

## 2. Spec

Load `to-spec`. Publish to `spec.md`.

**Done when:** `spec.md` exists and Quinn agreed to the seams.

## 3. Tickets

Load `to-tickets` with `spec.md`. Publish as local files.

**Done when:** Quinn approved the breakdown and one file per ticket is in `issues/`.

## 4. Build

Load `implement-spec` with `spec.md` and `issues/`, with these changes:

- **Step 3**: use the integration branch; create nothing, open no PR.
- **Step 4**: start only frontier tickets. A ticket that already has a worktree or branch from an earlier run → its implementer continues there.
- **Step 5**: right after a ticket merges into the integration branch, set its `**Status:**` to `done` in the main checkout. That line is what a re-run reads.
- **Step 7**: Skill tool `code-review`, fixed point `origin/<base>` (`develop`, else `main`), spec `spec.md`. Every ticket was already done on a re-run → still run it.
- **Step 8**: tickets are resolved by their `done` status; report the integration branch.

**Done when:** every ticket is done, the review findings are fixed on the integration branch, the ticket worktrees are removed, and the main checkout has the integration branch checked out.

## 5. Report

Print the integration branch, the tickets merged, the review fixes, and any loose ends. Next is `/send`.

**Done when:** the report is printed.
