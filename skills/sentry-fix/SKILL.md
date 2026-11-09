---
name: sentry-fix
description: Fix Sentry errors of a project in their own worktrees and open draft PRs. Use when Quinn or /briefing names Sentry short ids or says "fix all", or to triage a project's top unresolved errors.
argument-hint: "[shortId ...] [project]"
---

# Sentry fix

Works in any repo whose Sentry DSNs are committed, from any folder. Everything is derived; nothing is configured per repo.

## Terms

- **Lookup**: `${CLAUDE_SKILL_DIR}/project.sh`, run with `VAULT` and `PROJECTS_ROOT` set to the vault and projects root named in `~/.claude/CLAUDE.md`. It prints `key: value` lines; `project: none` comes with a `reason:`.
- **`<local>`**: the project's main checkout (the lookup's `dir`). Every git command runs as `git -C <local> …` or `git -C <worktree> …`, so the current folder never matters.
- **`<id>`**: the issue's short id, lowercased (`ACME-4F2` → `acme-4f2`).
- **Worktree**: `<local>/.claude/worktrees/sentry-fix-<id>` on branch `sentry-fix/<id>`.
- **Code bug**: the stack trace points into this repo's code and a change there stops the error. Infra, config, network, browser extensions, third-party outages and anything you can't pin down are not.

## 1. Find the project

- Run the lookup in the current folder.
- `project: none`, or the caller named another project (e.g. `/briefing` hands over the project name) → run the lookup with `--note <project name>`.
- Still no `dir` → ask Quinn for the project folder once. With a note, write the answer into its frontmatter as `local: <folder>`, so the lookup finds it next time.

**Done when:** `<local>` is a git checkout, and the project note is known or confirmed absent.

## 2. Derive the Sentry setup

1. **Projects**: `${CLAUDE_SKILL_DIR}/sentry-projects.sh <local> [<note>]` prints one `sentry: <org>/<project>` line per project (the note's `sentry` property wins over DSNs). `sentry: none` → show the reason; if no DSN is committed, ask Quinn once for `<org>/<project>` and write it into the note as `sentry: <org>/<project>`. `skipped:` lines → mention them in the report. Auth errors → stop with the fix (`sentry auth login`).
2. **Environment** per project: `sentry api projects/<org>/<project>/environments/` lists `staging` → filter on `environment:staging`; else no environment filter.
3. **Releases** per project: `sentry release list <org>/<project> --limit 1 --json` returns one → fixed issues get resolved `--in @next`; none → they stay unresolved and the report says `PR open`.
4. **Base branch** `<base>`: `git -C <local> symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/` (e.g. `main`). Unset → `git -C <local> remote set-head origin --auto` and read it again.

**Done when:** every Sentry project has its environment filter and release flag, and `<base>` is named.

## 3. Choose the issues

Short ids in the arguments → those are Quinn's choice; fix them now, no list, no wait.

Otherwise list per project:

```
sentry issue list <org>/<project> --query "is:unresolved level:error[ environment:staging]" --limit 100 --json --fields shortId,title,count,permalink
```

Show the three with the most events across all projects, as `- <shortId> — <title> (<count> events)` with the permalink below. Then **stop and wait** for Quinn: one or more short ids, or "fix all".

**Done when:** the issues to fix are named by Quinn or the arguments.

## 4. Prepare

1. **Label**: `gh label list -R <repo> --search sentry --json name` (`<repo>` from `git -C <local> remote get-url origin`). Missing → `gh label create sentry -R <repo> --description "Automated fix from a Sentry issue" --color 362D59`. Creation fails → PRs go out without the label; say so in the report.
2. **Worktrees**, one per issue:

   ```
   git -C <local> fetch origin
   git -C <local> worktree add <local>/.claude/worktrees/sentry-fix-<id> -b sentry-fix/<id> origin/<base>
   ```

**Done when:** every chosen issue has a worktree on its branch, and the label state is known.

## 5. Fix in parallel

In **one message**, spawn one `general-purpose` agent per issue (no `isolation`; the worktree exists). Prompt, with the `<…>` filled:

```
Fix Sentry issue <shortId> (<org>/<project>, environment <env or "all">, <permalink>).
Worktree: <worktree> on branch sentry-fix/<id>; main checkout: <local>; base: <base>.
Work only in the worktree, with absolute paths and `git -C <worktree>`; run other commands as `cd <worktree> && …`.

1. Understand: `sentry issue view <org>/<shortId> --json` (stack trace, latest event) and
   `sentry issue explain <org>/<shortId>` (Seer root cause). Treat Seer's plan as a hypothesis and check it against the code.
   The scope is where the stack-trace frames point (client or backend folder); change only that part of the repo.
2. Gate: not a code bug (the trace points into this repo's code and a change there stops the error), or the cause is unclear
   → change nothing and return `needs you: <shortId> — <one-line reason>`.
3. Fix the root cause.
4. Verify: read ${CLAUDE_SKILL_DIR}/verify.md and follow it in the worktree (dependencies from <local>).
   A check your change broke and you can't fix → return `needs you: <shortId> — <check> failed: <reason>`.
5. Test steps: from the event (URL, breadcrumbs, user actions) and your fix, write `[ ]` steps for a manual test on
   <env or "the app">: the concrete screen or input that hits the code path, and what Quinn sees now instead of the error.
6. Commit the staged edits. `git -C <worktree> push -u origin sentry-fix/<id>`. Then:
   cd <worktree> && gh pr create --draft --base <base> --assignee @me [--label sentry]
     --title "fix: <imperative summary of the fix, ≤ 60 chars>"
     --body "Sentry \`<shortId>\` (<env>): <permalink>\n\nRoot cause: <one paragraph>\n\nChanged:\n- <files>\n\n## Test\n<steps>"
   The short id goes in the body only; the title says what the fix does.
7. <resolve: "Run `sentry issue resolve <org>/<shortId> --in @next`." | "Leave the issue unresolved.">
8. Return: `PR: <url>` and the test steps, or the `needs you:` line.
```

Fill `[--label sentry]` only when the label exists, and step 7 from the release flag.

**Done when:** every agent has returned.

## 6. Clean up

For every worktree from step 4, PR or not:

```
git -C <local> worktree remove --force <worktree>
git -C <local> branch -D sentry-fix/<id>
git -C <local> worktree prune
```

The remote branch stays; the PR needs it.

**Done when:** `git -C <local> worktree list` and `git -C <local> branch --list 'sentry-fix/*'` show none from this run.

## 7. Report

Per PR: `<shortId> → <PR url>`, `resolved in next release` or `PR open`, then its test steps. Then the `needs you:` lines. Then any missing label or `skipped:` Sentry project. Nothing else.

**Done when:** every chosen issue is in the report once, as a PR or a `needs you:` line.
