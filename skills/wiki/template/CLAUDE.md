# Wiki

This repo is one project's shared knowledge, kept as Markdown pages. Everyone on the project feeds it from their own notes, and Claude maintains it.

## Layout

- Pages sit at the repo root, one topic per page, named in kebab case (`pricing-model.md`).
- `index.md` lists every page with a one-line summary.
- `log.md` is the source log: one line per ingested source.
- `.local` names one person's brain folder and project-notes folder on this machine. Git ignores it.

## Files

- `INGEST.md`: the steps of an ingest run. Follow it when asked to "ingest"; the daily wiki task follows it too.
- `setup-prompt.md`: the steps that connect this wiki to a person's notes. Follow it when someone says "set up".

## Rules

- A page holds what the team needs to know, written from sources. Raw sources stay on each person's machine.
- The project-notes folder in `.local` is the only source location.
