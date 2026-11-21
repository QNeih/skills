---
name: start-project
description: Start what the current project needs to show its current state (dev servers, containers) and open it in the browser.
disable-model-invocation: true
---

# Start project

`/start-project` starts every entry of the project's run file (`.claude/launch.json`) and opens `http://localhost:<port>` of the first entry with a port in the default browser. A project without a run file gets entries suggested from its compose file or package scripts, written once Quinn confirms. A project with nothing to run starts nothing. The dashboard's "e" key runs this skill in a session in the main checkout.

The dev servers belong to this session's folder: `/send` stops a ticket worktree's servers, and the dashboard stops them when it archives the session.

## 1. Folder

`<dir>` is `git rev-parse --show-toplevel` from the current folder, or the current folder without git. Run:

```bash
bash ${CLAUDE_SKILL_DIR}/runnable.sh <dir>
```

- `run file:` → step 3.
- `suggest from:` lines → step 2.
- `nothing to run` → say "Nothing to run in `<dir>`: no `.claude/launch.json`, compose file, or `dev` or `start` script in a `package.json`." and stop.
- `error:` → show it and stop.

**Done when:** you know which step comes next, or you stopped.

## 2. Suggest a run file

Read every source the `suggest from:` lines name, and draft one entry per thing to start, in the shape `{ "name": …, "runtimeExecutable": …, "runtimeArgs": [ … ], "port": … }`:

- Compose file → `docker`, `["compose", "-f", "<path>", "up"]`, in the foreground (no `-d`). `port`: the host port the compose file publishes for the service with the UI.
- `package.json` script → the package manager its lockfile names (`npm` without one), `["--prefix", "<subfolder>", "run", "<script>"]` (no `--prefix` at the top level; `pnpm`/`yarn` take `--dir`). `port`: the one its script or config sets, else the framework's default (Vite 5173, Next 3000).
- A source covered by another entry (a compose file that already runs the app a script would start) → leave it out.

The entry with the UI goes first: its port is the URL. Show the drafted file and ask Quinn to confirm or correct it. Confirmed → write `<dir>/.claude/launch.json` as `{ "version": "0.0.1", "configurations": [ … ] }`, one entry per line. Declined → start nothing and stop.

**Done when:** the run file is written as Quinn confirmed it, or Quinn declined and you stopped.

## 3. Start

An App session (the `preview_start` tool is available):

1. `python3 ${CLAUDE_SKILL_DIR}/start.py ports <dir>`
2. `preview_start` with the name of each `start:` line.
3. `python3 ${CLAUDE_SKILL_DIR}/start.py wait <dir>`

Any other session:

```bash
python3 ${CLAUDE_SKILL_DIR}/start.py up <dir>
```

It starts each entry detached, logs to `$TMPDIR/start-project/<project>-<entry>.log`, and waits up to 60 s for every port to listen from `<dir>`. Its lines:

- `running:` the entry already listens from `<dir>`; nothing started.
- `moved:` another folder holds the port; the entry moved to a free port in `launch.json`.
- `taken:` a container port another program holds; the entry was not started.
- `started:`, `up:` the entry started; its port listens.
- `no answer:` the port did not listen in 60 s; the log's last 20 lines follow when there is a log (App session: read `preview_logs` instead).
- `url:` the address to open.
- `error:` an entry could not start; the others still ran.

**Done when:** the script finished and you have its lines.

## 4. Open

A `url:` line → `open <url>`. None → open nothing.

**Done when:** the URL is open, or you know why there is none.

## 5. Report

- each entry: running, started, moved (old and new port), taken (by which command), no answer (with the log lines), or the error
- the URL opened, or why none: no entry has a port, or the first one did not answer
- a run file written in step 2 or a port moved in step 3: `.claude/launch.json` is changed and left uncommitted
- a `docker` entry started: its containers keep running until `docker compose down`
