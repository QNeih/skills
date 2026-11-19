# Ingest

The steps of one ingest run: turn one person's new sources into wiki pages and publish them. The daily wiki task follows them, and so does anyone who says "ingest" in this wiki.

`<wiki>` is this file's folder as an absolute path. Its `CLAUDE.md` holds the page layout; read it unless it is already in context.

A **source** is a file in the person's project-notes folder: a meeting transcript, a note, a document. The wiki gets a **digest** of each source: what the team needs to know, in your own words. The source itself stays where it is, because a transcript is private to the person who has it and the wiki is shared.

## 1. Notes folder

Read `notes:` from `<wiki>/.local`. No `.local`, or the folder is gone → stop: "Not set up: open `<wiki>` in Claude and say "set up"."

`<notes>` is the only source location. A source may link to notes elsewhere in the brain; those belong to other customers or to the person alone, so the link stays a link and the run reads inside `<notes>` only.

`<me>` is the output of `git -C "<wiki>" config user.name`.

**Done when:** `<notes>` is an existing folder and `<me>` is set.

## 2. Pull

`git -C "<wiki>" remote get-url origin` fails → the wiki is local only: skip this step and step 7.

```bash
git -C "<wiki>" pull --rebase origin main
```

A conflict → **Conflicts** below.

**Done when:** the wiki holds the remote's latest pages and source log.

## 3. Sources

List the candidates:

```bash
cd "<notes>" && find . -type f -not -path './wiki/*' -not -path '*/.*' -not -name '* Board.md'
```

That leaves out the wiki, the board file and hidden files. Also drop `<wiki>`'s own files when it lies inside `<notes>` under another name.

Each file left is a source with:

- **date**: the date in its file name, else its frontmatter `date:`, else the file's modification date. Written `YYYY-MM-DD`.
- **title**: the file name without date and extension.
- **kind**: `meeting` (a transcript or minutes), `note` (the person's own writing), or `document` (a file from someone else, such as a spec or a mail).

Read the source log, `<wiki>/log.md`, and sort every source by it before opening any source. A dated file name gives date and title without opening the file; open a file at this point only when its name has no date and you need its frontmatter.

A source is **logged** when a line has its date and a title naming the same meeting, note or document. The title may be worded differently, since the line may come from a teammate's copy.

- **New**, not logged → ingest it in step 4.
- **Done**, logged with `<me>` on its line → it stays closed. Reading it again is the cost the source log saves.
- **Known**, logged by others only → compare it in step 4. Keep its log line at hand for step 5.

A file you cannot read (audio, an image, a broken file) is no source: note it for the report.

**Done when:** every listed file is new, done, known or unreadable, and every done source is still closed.

## 4. Pages

**New source**: read it in full. Write its digest into pages: decisions with their reasons, facts and figures, open questions, who does what by when. A page is one topic, so a source usually feeds several pages, and a topic that has a page gets its page updated; a topic without one gets a new page. End each point with its source, `(<title>, <date>)`.

**Known source**: the team already worked it through from a teammate's copy. Read this copy next to the pages its log line names and add only what those pages lack, such as this person's own remarks in the file. Nothing lacking → the pages stay as they are.

A digest states things in your own words. Quote a sentence only when its exact wording matters, such as an agreed formulation.

Then bring `<wiki>/index.md` in line with the pages: one line per page, sorted by title.

```markdown
- [Pricing model](pricing-model.md): how the offer is priced and which discounts apply
```

**Done when:** every new and known source is worked through, and `index.md` lists every page.

## 5. Source log

`<wiki>/log.md` has one line per source; a new line goes at the end:

```markdown
- <date> · <title> · <kind> · <who> · <pages>
- 2026-11-12 · Kickoff with sales · meeting · Mara Lind, Quinn Neihaus · pricing-model, stakeholders
```

`<who>` names everyone who ingested or compared the source; `<pages>` names the pages it changed, by file name without `.md`.

- New source → add its line, with `<me>`.
- Known source → edit the line it has: add `<me>` to `<who>` and the pages you changed to `<pages>`. Date, title and kind stay as the teammate wrote them.

**Done when:** `log.md` has one line per source, and every new and known source has `<me>` on its line.

## 6. Commit

Nothing changed in `<wiki>` → no commit; go to step 7.

Else one commit for the run, its message naming every new and known source:

```bash
git -C "<wiki>" add -A
git -C "<wiki>" commit -m "Ingest: Kickoff with sales (2026-11-12), Tech sync (2026-11-17)"
```

More than three sources → the subject is `Ingest <n> sources` and the body lists them, one per line.

**Done when:** `git -C "<wiki>" status --porcelain` prints nothing.

## 7. Push

```bash
git -C "<wiki>" push origin main
```

Rejected, because a teammate pushed meanwhile → `git -C "<wiki>" pull --rebase origin main`, then push once more. A conflict → **Conflicts**. A second rejection → leave the commit local and report git's message.

**Done when:** `git -C "<wiki>" status -sb` shows `main` level with `origin/main`, or the report says why not.

## 8. Report

- each new and known source with the pages it changed
- how many sources were skipped as done
- files you could not read
- pushed, local only (no origin), or left local with the cause

**Done when:** the report is printed.

## Conflicts

A pull can stop on a file a teammate changed too. Merge it so both sides' content survives:

- `log.md`: keep both lines. The same source on both sides becomes one line with both names and all pages.
- a page: keep both sides' points.
- `index.md`: keep both entries.

Then `git -C "<wiki>" add -A` and `git -C "<wiki>" -c core.editor=true rebase --continue`.

A file you cannot merge without dropping someone's content → `git -C "<wiki>" rebase --abort`. Your commit stays local and the remote stays as it is. Report the files in conflict and stop the run; the person resolves it by hand.
