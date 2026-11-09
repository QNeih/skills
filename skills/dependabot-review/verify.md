# Verify recipe

How to prove a change in a worktree is safe: find the repo's own verify commands, give the worktree its dependencies, run the commands, stage only real edits.

## 1. Find the commands

Look in this order and take the first source that names commands for the folder the change touches:

1. **CI config**: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `azure-pipelines.yml`, `Jenkinsfile`, `bitbucket-pipelines.yml`. Take the steps CI runs on pull requests for that folder.
2. **Agent docs**: `CLAUDE.md`, `AGENTS.md` in the repo root and in the folder.
3. **Manifest scripts**: `package.json` scripts, `Makefile`, `*.csproj` / `*.sln` (`dotnet build`, `dotnet test`), `pyproject.toml`, `Cargo.toml`, `go.mod`, …

The recipe is build → lint/typecheck → tests, leaving out any that don't exist. Several variants (`build:development`, `build:production`) → the one CI runs on pull requests, else the development one. Skip deploy, release, publish and anything that needs secrets. Write the commands down exactly with the folder each runs in.

**Done when:** every command of the recipe is written down with its folder, or you've noted that the repo has none.

## 2. Give the worktree its dependencies

- **Lockfile unchanged** (the usual case): symlink each installed dependency folder from the main checkout into the same place in the worktree, e.g. `ln -s <main>/client/node_modules <worktree>/client/node_modules`. Find them with `git -C <main> status --ignored --short` (`node_modules`, `.venv`, `vendor`, …). Nothing installed in the main checkout → run the lockfile-strict install in the worktree.
- **Lockfile changed** (a dependency update): run the lockfile-strict install in the worktree (`npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`, `dotnet restore --locked-mode`, `pip install -r` with hashes, …).

**Done when:** the recipe's first command finds its dependencies.

## 3. Run

Run each command in its folder. Record pass/fail and, for a failure, the first ~20 error lines. A command that also fails on the base branch is pre-existing; note it and don't count it against the change.

**Done when:** every command has a recorded result.

## 4. Stage only real edits

A symlinked `node_modules` is a file to git, so ignore rules written for the folder (`node_modules/`) miss it. Stage the files you edited by explicit path (`git add <path> …`), then check:

```
git -C <worktree> diff --cached --name-only
```

The list holds only source files you changed: no dependency link or folder, no lockfile unless the change is a dependency update, no build output. Unstage anything else with `git restore --staged <path>`.

**Done when:** the staged list is exactly your edits.
