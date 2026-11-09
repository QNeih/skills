---
name: dependabot-review
description: Check every open Dependabot PR in the current GitHub repo, in parallel — does it break the build, could it change runtime behaviour. Extra text = filters and context.
argument-hint: "[filter/context, e.g. 'only label javascript', '#3534 #3535', 'npm only, we never use X']"
disable-model-invocation: true
---

Read-only verdict on each open Dependabot PR on two axes:

- **Build** — does the PR break install, build, lint/typecheck or tests, *compared to the base branch*?
- **Behaviour** — could the version change alter what the software does at runtime, given how *this repo* uses the package?

The skill reports. Merging, closing, approving, commenting and pushing are the user's call.

## User context

`$ARGUMENTS` is free text. Read it as two kinds of input:

- **Filters** — label, ecosystem, directory, PR numbers, "majors only". Apply them in step 2.
- **Context** — facts about the repo or the team ("we pin X on purpose", "TS majors are always blocked"). Pass it verbatim into every subagent prompt.

No arguments = all open Dependabot PRs, no extra context.

## Process

### 1. Preflight

Run `gh repo view --json nameWithOwner,defaultBranchRef`. If it fails (no GitHub remote, gh not authenticated), stop and tell the user which.

Read the repo's agent instructions (`CLAUDE.md`, `AGENTS.md`, memory) for known dependency facts — blocked upgrades, broken test setups, build quirks. These count as context too.

**Done when:** you have the repo, its default branch, and its dependency facts.

### 2. List the PRs

```
gh pr list --author app/dependabot --state open --limit 200 \
  --json number,title,url,labels,headRefName,baseRefName,body
```

Apply the filters. Also include PRs from `dependabot-preview[bot]` or with branch prefix `dependabot/` if the author query returns nothing. Empty list → report "no matching Dependabot PRs" and stop.

For each PR record: package(s), from → to version, semver jump (patch/minor/major), manifest directory (the `in /path` part of the title, or the changed files). Grouped PRs (`Bump the X group with N updates`) bump several packages — list every one.

**Done when:** every matching PR has its packages, versions, jump and directory recorded.

### 3. Build recipe

Read `${CLAUDE_SKILL_DIR}/verify.md` and do its step 1 once per manifest directory. Every subagent runs the same commands.

**Done when:** every manifest directory from step 2 has a written recipe, or a note that the repo has none.

### 4. Fan out

In **one message**, spawn:

- **one baseline agent per manifest directory** — checks out the base branch (`git fetch origin <base> && git checkout --detach origin/<base>`), follows steps 2–3 of verify.md in that directory with the recipe, and reports every failing command with its first error lines.
- **one PR agent per PR** — prompt below.

Every agent gets `isolation: "worktree"`, `subagent_type: "general-purpose"`, the recipe, and the absolute path of `${CLAUDE_SKILL_DIR}/verify.md`. Size batches to memory so parallel builds don't starve the machine: batch size = (total RAM from `sysctl -n hw.memsize` / `free -b`, minus 4 GB for the system) ÷ the recipe's peak build memory (its heap flag, e.g. `--max-old-space-size=8192` → 8 GB; else assume 2 GB), capped at 8, minimum 1. Parallel worktree creation can race in git (`failed to read …/commondir`) — relaunch that agent once in the next batch. Identify the failed one by its description, not by position in the result list.

PR agent prompt (fill the `<…>`):

```
Review Dependabot PR #<n> (<url>) in <repo>. Read-only: no pushes, comments, approvals or merges.
Packages: <package: from → to, jump> (all of them for a group PR)
Manifest directory: <dir>
Recipe: <exact commands>
Verify recipe: <absolute path of verify.md>
User context: <$ARGUMENTS context + repo facts from step 1, or "none">

1. Build. `gh pr checkout <n> --detach` in this worktree, then follow steps 2–3 of the verify recipe in <dir> with the recipe above (the PR changes the lockfile, so do the lockfile-strict install). Also run `gh pr checks <n>` and record CI status.
   For every failing command, trace the error to its root cause — removed/renamed export, changed signature, peer-dependency mismatch, stricter types, or environment (registry auth, network, missing tool) — and give the concrete fix: file:line, before → after. The installed package's own types/docs in node_modules (or equivalent) are the source of truth for the new API.
2. Behaviour. For every package:
   a. Find what changed between the two versions: the release notes / changelog / commits Dependabot put in the PR body, then the package's changelog, GitHub releases or migration guide for every version in between. Majors: read the migration guide in full. Nothing found anywhere → say so in NOTES; it caps BEHAVIOUR at low, never none.
   b. List each breaking change, deprecation, default change, and behaviour fix that a caller could notice.
   c. For each one, search this repo for usage that hits it (imports, the specific APIs, config files, CLI flags, styles). Cite file:line, or "no usage found" with the search you ran. An indirect package (`dependency-type: indirect` in the PR body) is used through the direct dependency that pulls it in (`npm ls <pkg>` or equivalent) — search for that one's usage.
   d. Check the lockfile diff for transitive packages that also moved a major, and for new peer-dependency conflicts.
   e. For every affected usage, write a manual test: an action in the running app (what to open, click, or run), the package it exercises, and the change it covers.
3. Return exactly:
   BUILD: <per command: pass|fail + error excerpt + root cause + fix> ; CI: <status>
   BEHAVIOUR: none | low | high
   EVIDENCE: <each change from 2b → affected file:line or "unused here">
   DEV-ONLY: yes|no (yes = used only by tests, lint, or type checking; build tooling that produces the shipped bundle counts as no)
   MANUAL TESTS: <[ ] items from 2e, or "none">
   NOTES: <anything the user must know>
```

**Done when:** every PR agent and every baseline agent has returned.

### 5. Verdicts

For each PR:

- **Build** = `breaks` only for commands that fail on the PR and pass on the baseline. Commands that fail on both are `pre-existing`, never blamed on the PR.
- **Behaviour** = the agent's level, checked against its evidence. `high` needs a cited usage that hits a listed change. `none` needs every listed change marked unused or dev-only.
- **Recommendation**: `merge` (build ok, behaviour none/low) · `merge after fix` (the agent's root cause and file:line fix) · `test by hand first` (the agent's manual tests) · `close` (name why, e.g. a blocked major).

Then clean up: agents moved their worktree to another commit, so they are not auto-removed and each holds a full install (~1 GB for npm). For every worktree this run created, check `git -C <wt> status --porcelain` shows no tracked changes, then `git worktree remove --force <wt>` and `git branch -D <its worktree-agent-* branch>`. Touch no worktree from another run.

**Done when:** every PR from step 2 has a Build verdict, a Behaviour verdict with evidence, and a recommendation, and `git worktree list` shows no worktree from this run.

### 6. Report

One table, then per-PR notes only where the recommendation isn't plain `merge` — for `merge after fix` the root cause and fix, for `test by hand first` the manual-test checklist:

| PR | Package(s) | From → to | Build | Behaviour | Recommendation |
|----|-----------|-----------|-------|-----------|----------------|

Below it: the pre-existing baseline failures per directory, and any PRs that could conflict with each other (same lockfile, overlapping packages — merging one forces a rebase of the others).

**Done when:** the table has one row per PR from step 2, and every recommendation other than `merge` has its note.
