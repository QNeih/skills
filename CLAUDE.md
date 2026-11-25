# skills

Rules for changing this repo. Terms: `GLOSSARY.md`.

## Git

- Ticket work (`/work` → `/send`) goes through a PR; `/send` merges this repo's PRs (squash, delete the branch). No CI or reviewer.
- Any other skill change: commit straight to `main` and push.

## Skill text

- `SKILL.md` and every other file an agent reads (this file, a file a skill points to) follow the `writing-for-agents` skill. Load it before writing or reviewing one.
- Only a change that creates a skill, or rewrites most of an existing one, goes through the `skill-creator` skill, once: draft, then its eval loop. Where its writing guide disagrees with `writing-for-agents`, `writing-for-agents` wins.
- For a skill that writes to git, a board or the vault, `skill-creator`'s test runs happen inside a fixture from `tests/lib.sh`, so the real vault, real boards (GitHub Projects) and real projects stay untouched.

## README

A change that adds or removes a skill, or changes a skill's flow (its routes, its stops for Quinn, the skills it hands off to), updates `README.md` in the same change: the `## Workflow` diagram, the command list and the skills table.

## Tests

- A new script a skill runs gets a script test in `tests/test-*.sh`. `bash tests/run.sh` passes before a commit.
- A change to the steps of a skill that has a live test (`tests/live-<skill>*.sh`) runs that file with `bash` before the commit, whatever the token cost. Run only that file, and report its result.
- A new skill is tested through `skill-creator`'s eval loop; write a live test for it only when Quinn asks.
