#!/usr/bin/env python3
"""Local dashboard backend: briefing, project boards, tickets, Claude desktop sessions, weather.

    python3 server.py [--port 4777]

Serves index.html from this folder and a JSON API on 127.0.0.1 only. Python 3.9 stdlib.
Env overrides: VAULT, PROJECTS_ROOT, BRIEFING_STATE (the real state copied per run, never written).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import unicodedata
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILLS = HERE.parent
GATHER = SKILLS / "briefing" / "gather.sh"
PROJECT_SH = SKILLS / "ticket" / "project.sh"
HOME = Path.home()
VAULT = os.environ.get("VAULT", str(HOME / "Library/Mobile Documents/iCloud~md~obsidian/Documents/lise"))
PROJECTS_ROOT = os.environ.get("PROJECTS_ROOT", str(HOME / "Projects"))
BRIEFING_STATE = Path(os.environ.get("BRIEFING_STATE", str(HOME / ".claude/briefing")))
SESSIONS_DIR = HOME / "Library/Application Support/Claude/claude-code-sessions"
TRANSCRIPTS_DIR = HOME / ".claude/projects"
LINK = "claude://claude.ai/epitaxy/{}"
ORDER_FILE = HOME / ".claude/dashboard/order.json"
# A session whose transcript hasn't changed for this long is not running, whatever its last line says
# (a crashed or killed turn leaves no end_turn behind).
RUNNING_STALE_MS = 10 * 60 * 1000


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def now_ms():
    return int(time.time() * 1000)


def nfc(s):
    return unicodedata.normalize("NFC", s or "")


def script_env():
    return dict(os.environ, VAULT=VAULT, PROJECTS_ROOT=PROJECTS_ROOT)


def run(cmd, env=None, timeout=60):
    """Run a command; returns (exit code, stdout+stderr)."""
    p = subprocess.run(cmd, env=env or script_env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       stdin=subprocess.DEVNULL, timeout=timeout, cwd=tempfile.gettempdir())
    return p.returncode, p.stdout.decode("utf-8", "replace")


# --- briefing --------------------------------------------------------------------------------

LINE_KINDS = [("prompt ", "prompt"), ("commit ", "commit"), ("left off:", "left-off"), ("next:", "next"),
              ("jira ", "jira"), ("sentry ", "sentry"), ("dependabot:", "dependabot"), ("note ", "note"),
              ("error:", "error")]
DID_KINDS = {"prompt", "commit", "left-off"}  # the dashboard shows what's next, not what was done


def line_kind(line):
    for prefix, kind in LINE_KINDS:
        if line.startswith(prefix):
            return kind
    return "other"


def parse_gather(out):
    """gather.sh output → header, today lines, project sections (Did lines dropped)."""
    header, today, projects, section = {}, [], [], None
    keys = {"today": "today", "last workday": "lastWorkday", "since": "since"}
    for line in out.splitlines():
        if not line.strip():
            continue
        if line.startswith("# "):
            name = line[2:].strip()
            if name == "Today":
                section = today
            else:
                section = {"name": name, "lines": []}
                projects.append(section)
            continue
        if section is None:
            k, _, v = line.partition(": ")
            if k in keys:
                header[keys[k]] = v
            elif line.startswith("error:"):
                raise RuntimeError(line)
            continue
        if section is today:
            today.append(line)
        else:
            kind = line_kind(line)
            if kind not in DID_KINDS:
                section["lines"].append({"kind": kind, "text": line})
    return {"header": header, "today": today, "projects": [p for p in projects if p["lines"]]}


class Briefing:
    """gather.sh in a background thread against a throwaway copy of the briefing state."""

    def __init__(self):
        self.lock = threading.Lock()
        self.data = {"status": "running", "generatedAt": None, "header": {}, "today": [], "projects": [],
                     "error": None}
        self.thread = None

    def get(self):
        with self.lock:
            return json.loads(json.dumps(self.data))

    def start(self):
        with self.lock:
            if self.thread and self.thread.is_alive():
                return dict(status="running")
            self.data["status"] = "running"
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()
            return dict(status="running")

    def _run(self):
        tmp = tempfile.mkdtemp(prefix="dashboard-briefing-")
        try:
            state = Path(tmp) / "state"
            if BRIEFING_STATE.is_dir():
                shutil.copytree(BRIEFING_STATE, state)
            else:
                state.mkdir()
            env = dict(script_env(), BRIEFING_STATE=str(state))
            code, out = run(["bash", str(GATHER)], env=env, timeout=600)
            if code != 0:
                raise RuntimeError("gather.sh exit {}: {}".format(code, out.strip()[-500:]))
            result = parse_gather(out)
            with self.lock:
                self.data = dict(status="ready", generatedAt=now_ms(), error=None, **result)
        except Exception as e:
            traceback.print_exc()
            with self.lock:
                self.data.update(status="error", error=str(e), generatedAt=now_ms())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


BRIEFING = Briefing()


# --- projects and boards ---------------------------------------------------------------------

def active_projects():
    """Names of active projects, from gather.sh --contacts (it prints `# <name>` per active project)."""
    code, out = run(["bash", str(GATHER), "--contacts"])
    if code != 0:
        raise RuntimeError("gather.sh --contacts: " + out.strip())
    return [l[2:].strip() for l in out.splitlines() if l.startswith("# ")]


def lookup(name):
    code, out = run(["bash", str(PROJECT_SH), "--note", name])
    info = {}
    for line in out.splitlines():
        k, sep, v = line.partition(": ")
        if sep:
            info.setdefault(k.strip(), v)
    return info


CARD_RE = re.compile(r"^- \[[ xX]\] \*\*([A-Z][A-Z0-9]*-\d+) · (.+?)\*\*(.*)$")
ID_RE = re.compile(r"[A-Z][A-Z0-9]*-\d+")


def parse_board(text):
    """Vault Kanban board → cards in board order: {id, title, column, lines, needs, urgent}."""
    cards, column, card = [], None, None
    for raw in text.splitlines():
        if raw.startswith("## "):
            column, card = raw[3:].strip().lower(), None
            continue
        m = CARD_RE.match(raw)
        if m and column:
            card = {"id": m.group(1), "title": m.group(2).strip(), "column": column,
                    "lines": [raw[6:].strip()], "needs": [], "urgent": False}
            cards.append(card)
        elif card and raw.startswith("\t"):
            line = raw.strip()
            card["lines"].append(line)
            if re.match(r"(Braucht|Needs):", line):
                card["needs"] += ID_RE.findall(line)
        else:
            card = None
    for c in cards:
        c["urgent"] = any("#urgent" in l for l in c["lines"])
        c["goal"] = card_goal(c["lines"][1:])
    return cards


def card_goal(desc):
    """The ticket's goal in one sentence: a `Goal:`/`Ziel:` line, else the first sentence of the
    first description line (meta lines Branch/PR/Braucht/Needs skipped). Same rule as briefing/gather.sh's vault_next."""
    for line in desc:
        m = re.match(r"(?:Goal|Ziel):\s*(.+)", line)
        if m:
            return m.group(1).strip()
    desc = [l for l in desc if not re.match(r"(Branch|PR|Braucht|Needs)[ :]", l)]
    if not desc:
        return ""
    return re.split(r"(?<=[.!?])\s", desc[0], 1)[0].strip()


def blocked_by(card, cards):
    done = {c["id"] for c in cards if c["column"] == "done"}
    return [i for i in card["needs"] if i not in done]


def rank_vault(cards):
    """Unblocked To do cards, #urgent first, then board order (VAULT.md › Pick)."""
    todo = [c for c in cards if c["column"] == "to do" and not blocked_by(c, cards)]
    return sorted(todo, key=lambda c: not c["urgent"])


JIRA_BUCKETS = [("bug", "defect", "bugfix", "sub-bug"), ("story", "user story"), ("epic",), ("task",),
                ("spike", "research", "investigation")]


def jira_bucket(type_name):
    t = (type_name or "").lower()
    for i, names in enumerate(JIRA_BUCKETS):
        if t in names:
            return i
    return len(JIRA_BUCKETS)


def jira_issue(item):
    f = item["fields"]
    status = f.get("status") or {}
    return {"id": item["key"], "title": f.get("summary") or "", "column": status.get("name") or "",
            "cat": (status.get("statusCategory") or {}).get("key"), "type": (f.get("issuetype") or {}).get("name"),
            "prio": int((f.get("priority") or {}).get("id") or 99), "labels": f.get("labels") or []}


def rank_jira(issues):
    """PICKING.md › Rank: hotfix, priority, type bucket, In Progress before To Do; the JQL's
    `ORDER BY updated DESC` is the input order, so the stable sort keeps newest first on ties.
    Hotfix only looks at summary, type and labels (the search doesn't return descriptions)."""
    def key(i):
        hot = re.search("hotfix", " ".join([i["title"], i["type"] or ""] + i["labels"]), re.I)
        return (0 if hot else 1, i["prio"], jira_bucket(i["type"]), 0 if i["cat"] == "indeterminate" else 1)
    return sorted(issues, key=key)


def jira_search(jql):
    code, out = run(["acli", "jira", "workitem", "search", "--jql", jql, "--fields",
                     "key,summary,status,priority,issuetype,labels", "--json", "--paginate"])
    if code != 0:
        raise RuntimeError("Jira: " + (out.strip().splitlines() or ["acli failed"])[0] + " — acli jira auth login")
    return [jira_issue(i) for i in json.loads(out)]


def jira_board(key):
    """My open sprint tickets: In Progress category → inProgress; To Do category → next, ranked.
    Nothing assigned to me → next from the whole sprint (PICKING.md step 1) and mine=False: there is
    no top pick then, /ticket asks which one.
    Not checked: blocking links. acli's search refuses the `issuelinks` field, so PICKING's
    blocked check is skipped and blockedBy stays empty."""
    base = "project = {} AND sprint in openSprints() AND resolution = Unresolved".format(key)
    mine = jira_search(base + " AND assignee = currentUser() ORDER BY updated DESC")
    pool = mine or jira_search(base + " ORDER BY updated DESC")
    in_progress = [{"id": i["id"], "title": i["title"]} for i in mine if i["cat"] == "indeterminate"]
    nxt = [dict(id=i["id"], title=i["title"], column=i["column"], blockedBy=[], urgent=False)
           for i in rank_jira([i for i in pool if i["cat"] == "new"])]
    return nxt, in_progress, bool(mine)


def jira_key(info):
    board = info.get("board", "")
    if board == "jira-candidate":
        return info.get("key")
    m = re.search(r"(?:projects|browse)/([A-Z][A-Z0-9]+)", board)
    return m.group(1) if "atlassian.net" in board and m else None


def sentry_ids(text):
    ids = []
    for part in ("new", "regressed"):
        m = re.search(part + r": ([A-Z0-9 -]+?)(?:,|$)", text)
        if m:
            ids += m.group(1).split()
    return ids


def briefing_jumps(name, briefing):
    if briefing["status"] != "ready":
        return []
    section = next((p for p in briefing["projects"] if p["name"] == name), None)
    if not section:
        return []
    jumps, ids = [], []
    for line in section["lines"]:
        if line["kind"] == "sentry":
            ids += sentry_ids(line["text"])
    if ids:
        jumps.append({"key": "s", "label": "fix sentry", "action": "copy",
                      "arg": "/sentry-fix {} {}".format(" ".join(ids), name)})
    if any(l["kind"] == "dependabot" for l in section["lines"]):
        jumps.append({"key": "d", "label": "review dependabot", "action": "copy", "arg": "/dependabot-review"})
    for line in section["lines"]:
        m = re.match(r"note (\d+):", line["text"])
        if line["kind"] == "note" and m:
            jumps.append({"key": "n", "label": "done note " + m.group(1), "action": "note-done", "arg": m.group(1)})
    return jumps


def project_view(name, briefing, sessions):
    info = lookup(name)
    d = info.get("dir", "none")
    view = {"name": name, "dir": None if d == "none" else d, "board": info.get("board"), "key": info.get("key"),
            "error": None, "next": [], "inProgress": [], "jumps": [], "lastActivityAt": None, "running": 0}
    errors, top_pick = [], True
    if d == "none":
        errors.append("folder: " + info.get("reason", "not found"))
    try:
        if info.get("board") == "vault":
            cards = parse_board(Path(info["board-file"]).read_text(encoding="utf-8"))
            view["next"] = [dict(id=c["id"], title=c["title"], column=c["column"], goal=c["goal"],
                                 blockedBy=blocked_by(c, cards), urgent=c["urgent"]) for c in rank_vault(cards)[:3]]
            view["inProgress"] = [{"id": c["id"], "title": c["title"], "goal": c["goal"]}
                                  for c in cards if c["column"] == "in progress"]
        elif jira_key(info):
            view["key"] = jira_key(info)
            nxt, view["inProgress"], top_pick = jira_board(view["key"])
            view["next"] = nxt[:3]
    except Exception as e:
        traceback.print_exc()
        errors.append(str(e))
    view["error"] = "; ".join(errors) or None
    if view["next"] and top_pick:
        top = view["next"][0]["id"]
        view["jumps"].append({"key": "t", "label": "start /ticket " + top, "action": "copy", "arg": "/ticket " + top})
    view["jumps"] += briefing_jumps(name, briefing)
    if view["dir"]:
        mine = [s for s in sessions if in_dir(s, view["dir"])]
        acts = [s.get("lastActivityAt") or 0 for s in mine]
        view["lastActivityAt"] = max(acts) if acts else None
        view["running"] = sum(1 for s in mine if session_state(s) == "running")
    return view


def sort_projects(views, order=()):
    """Projects in Quinn's saved order first, in that order; the rest after them, most recent
    session activity first, projects with nothing to do last. Saved names that aren't active are ignored."""
    rank = {name: i for i, name in enumerate(order)}

    def idle(v):
        return not (v["next"] or v["inProgress"] or v["jumps"] or v["error"])
    saved = sorted((v for v in views if v["name"] in rank), key=lambda v: rank[v["name"]])
    rest = sorted((v for v in views if v["name"] not in rank), key=lambda v: (idle(v), -(v["lastActivityAt"] or 0)))
    return saved + rest


def read_order():
    if not ORDER_FILE.is_file():
        return []
    return json.loads(ORDER_FILE.read_text(encoding="utf-8"))["order"]


def save_order(body):
    order = body.get("order")
    if not isinstance(order, list) or not all(isinstance(n, str) for n in order):
        raise ApiError(400, "order must be a list of project names")
    ORDER_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(ORDER_FILE.parent), prefix=".order-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"order": order}, f, ensure_ascii=False, indent=2)
        os.replace(tmp, str(ORDER_FILE))
    except BaseException:
        os.unlink(tmp)
        raise
    return {"order": order}


def projects_view():
    briefing, sessions = BRIEFING.get(), load_sessions()
    with ThreadPoolExecutor() as pool:  # lookups and acli are slow; run the projects side by side
        views = list(pool.map(lambda n: project_view(n, briefing, sessions), active_projects()))
    return sort_projects(views, read_order())


# --- sessions --------------------------------------------------------------------------------

def load_sessions(root=None):
    out = []
    for f in sorted(Path(root or SESSIONS_DIR).glob("*/*/local_*.json")):
        out.append(json.loads(f.read_text(encoding="utf-8")))
    return out


def in_dir(session, d):
    d = nfc(d).rstrip("/")
    for p in (session.get("cwd"), session.get("originCwd")):
        p = nfc(p)
        if p and (p == d or p.startswith(d + "/")):
            return True
    return False


def transcript_path(session, root=None):
    root = Path(root or TRANSCRIPTS_DIR)
    cli = session.get("cliSessionId")
    if not cli:
        return None
    p = root / re.sub(r"[^A-Za-z0-9]", "-", session.get("cwd") or "") / (cli + ".jsonl")
    if p.is_file():
        return p
    found = sorted(root.glob("*/" + cli + ".jsonl"))
    return found[0] if found else None


def read_lines(path, tail_bytes=None):
    with open(path, "rb") as f:
        if tail_bytes:
            f.seek(0, 2)
            if f.tell() > tail_bytes:
                f.seek(f.tell() - tail_bytes)
                f.readline()  # drop the partial first line
            else:
                f.seek(0)
        for raw in f:
            try:
                yield json.loads(raw)
            except ValueError:
                continue  # a line still being written


COMMAND_RE = re.compile(r"<command-name>/?([^<]+)</command-name>(?:.*?<command-args>(.*?)</command-args>)?", re.S)


def user_text(content):
    """Text of a real user prompt, or None. Slash-command wrappers become `/name args`; other
    `<…>` strings and text blocks (system reminders, hook output) and tool results are skipped."""
    if isinstance(content, str):
        content = [{"type": "text", "text": content}]
    parts = []
    for b in content or []:
        if not isinstance(b, dict) or b.get("type") != "text":
            continue
        t = (b.get("text") or "").strip()
        if t.startswith("<"):
            m = COMMAND_RE.search(t)
            t = ("/" + m.group(1).strip() + " " + (m.group(2) or "").strip()).strip() if m else ""
        if t:
            parts.append(t)
    return "\n".join(parts) or None


def short_arg(inp):
    if not isinstance(inp, dict):
        return ""
    for k in ("command", "file_path", "path", "pattern", "url", "query", "skill", "description", "prompt"):
        v = inp.get(k)
        if isinstance(v, str) and v:
            break
    else:
        v = next((v for v in inp.values() if isinstance(v, str) and v), "")
    v = " ".join(v.split())
    return v if len(v) <= 80 else v[:79] + "…"


def parse_transcript(path, limit=200):
    """user / assistant / tool messages of the main thread; thinking and tool results dropped."""
    msgs = []
    for e in read_lines(path):
        if e.get("isSidechain") or e.get("isMeta") or e.get("type") not in ("user", "assistant"):
            continue
        content, ts = (e.get("message") or {}).get("content"), e.get("timestamp")
        if e["type"] == "user":
            t = user_text(content)
            if t:
                msgs.append({"role": "user", "text": t, "ts": ts})
            continue
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for b in content or []:
            if b.get("type") == "text" and b.get("text", "").strip():
                msgs.append({"role": "assistant", "text": b["text"].strip(), "ts": ts})
            elif b.get("type") == "tool_use":
                msgs.append({"role": "tool", "text": ("▸ " + b.get("name", "") + " " + short_arg(b.get("input"))).rstrip(),
                             "ts": ts})
    return msgs[-limit:]


_facts_cache = {}


def transcript_facts(path):
    """First real user prompt and every git branch the transcript recorded (a worktree session
    starts on claude/<name>; /ticket then cuts feature/<id> there). Cached per file version."""
    st = path.stat()
    key = (str(path), st.st_mtime_ns, st.st_size)
    if key not in _facts_cache:
        first, branches = None, set()
        for e in read_lines(path):
            if e.get("gitBranch"):
                branches.add(e["gitBranch"])
            if first is None and e.get("type") == "user" and not e.get("isSidechain") and not e.get("isMeta"):
                first = user_text((e.get("message") or {}).get("content"))
        _facts_cache[key] = {"firstPrompt": first, "branches": sorted(branches)}
    return _facts_cache[key]


END_REASONS = {"end_turn", "stop_sequence", "max_tokens", "refusal"}


def session_state(session, transcripts=None, now=None):
    """archived: isArchived.
    running: the transcript changed in the last 10 minutes and its last main-thread user/assistant
      line is not a finished turn (an assistant line with stop_reason end_turn etc.), nor an
      interrupt marker. So a tool call in flight or a tool result waiting for the model is running.
      A permission prompt also looks running; the files don't tell it apart.
    waiting: everything else; an idle unarchived session waits on Quinn.
    The app's own fields (lastTurnEdgeAt, postTurnSummary) only change at turn edges and lag
    behind, so they can't tell a running turn from a finished one."""
    if session.get("isArchived"):
        return "archived"
    path = transcript_path(session, transcripts)
    now = now if now is not None else now_ms()
    if not path or now - path.stat().st_mtime * 1000 > RUNNING_STALE_MS:
        return "waiting"
    last = None
    for e in read_lines(path, tail_bytes=512 * 1024):
        if e.get("type") in ("user", "assistant") and not e.get("isSidechain"):
            last = e
    if not last:
        return "waiting"
    msg = last.get("message") or {}
    if last["type"] == "assistant":
        return "waiting" if msg.get("stop_reason") in END_REASONS else "running"
    c = msg.get("content")
    text = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if isinstance(b, dict))
    return "waiting" if "[Request interrupted" in text else "running"


def session_summary(s):
    pts, wrap = s.get("postTurnSummary") or {}, s.get("turnWrapUp") or {}
    if pts.get("needs_action"):
        return "needs you: " + pts["needs_action"]
    return pts.get("status_detail") or wrap.get("description") or ""


def session_brief(s, transcripts=None):
    return {"sessionId": s["sessionId"], "title": s.get("title"), "name": (s.get("spawnedFrom") or {}).get("name"),
            "state": session_state(s, transcripts), "lastActivityAt": s.get("lastActivityAt"),
            "summary": session_summary(s), "link": LINK.format(s["sessionId"]),
            "prs": [p["url"] for p in s.get("prs") or [] if p.get("url")]}


def mentions(text, ticket_id):
    return bool(text) and re.search(r"(?<![A-Za-z0-9])" + re.escape(ticket_id) + r"(?![0-9])", text, re.I) is not None


def ticket_prompt_matches(prompt, ticket_id):
    """`/ticket <id>` or `/ticket <number>` (for the ticket's key) as the first prompt."""
    m = re.match(r"/ticket\s+([A-Za-z][A-Za-z0-9]*-\d+|\d+)\b", prompt or "")
    if not m:
        return False
    arg, num = m.group(1), ticket_id.rsplit("-", 1)[1]
    return arg.upper() == ticket_id.upper() if "-" in arg else int(arg) == int(num)


def ticket_sessions(ticket_id, project_dir, sessions, transcripts=None):
    """Sessions of the project for the ticket, each with its spawnedFrom descendants nested.
    A session matches when its title, branch (stored, or any recorded in its transcript) or
    spawnedFrom.title names the id, or its first prompt is `/ticket <id>` / `/ticket <number>`."""
    matched = set()
    for s in sessions:
        if not in_dir(s, project_dir):
            continue
        blob = [s.get("title"), s.get("branch"), (s.get("spawnedFrom") or {}).get("title")]
        if any(mentions(t, ticket_id) for t in blob):
            matched.add(s["sessionId"])
            continue
        path = transcript_path(s, transcripts)
        if not path:
            continue
        facts = transcript_facts(path)
        if ticket_prompt_matches(facts["firstPrompt"], ticket_id) or any(mentions(b, ticket_id) for b in facts["branches"]):
            matched.add(s["sessionId"])
    by_id = {s["sessionId"]: s for s in sessions}
    kids = {}
    for s in sessions:
        parent = (s.get("spawnedFrom") or {}).get("sessionId")
        if parent:
            kids.setdefault(parent, []).append(s)

    def node(s, seen):
        seen = seen | {s["sessionId"]}
        children = sorted((c for c in kids.get(s["sessionId"], []) if c["sessionId"] not in seen),
                          key=lambda c: c.get("createdAt") or 0)
        return dict(session_brief(s, transcripts), children=[node(c, seen) for c in children])

    def ancestor_matched(s):
        seen, p = set(), (s.get("spawnedFrom") or {}).get("sessionId")
        while p and p not in seen:
            if p in matched:
                return True
            seen.add(p)
            p = (by_id.get(p, {}).get("spawnedFrom") or {}).get("sessionId")
        return False

    roots = sorted((by_id[i] for i in matched if not ancestor_matched(by_id[i])),
                   key=lambda s: s.get("createdAt") or 0)
    return [node(s, set()) for s in roots]


def session_view(session_id):
    s = next((s for s in load_sessions() if s["sessionId"] == session_id), None)
    if not s:
        raise ApiError(404, "no session " + session_id)
    path = transcript_path(s)
    return {"sessionId": s["sessionId"], "title": s.get("title"), "state": session_state(s), "cwd": s.get("cwd"),
            "branch": s.get("branch"), "link": LINK.format(s["sessionId"]), "summary": session_summary(s),
            "messages": parse_transcript(path) if path else []}


# --- tickets ---------------------------------------------------------------------------------

def field(text, name):
    m = re.search(r"^" + re.escape(name) + r"\s*(.*)$", text, re.M)
    return m.group(1).strip() if m else None


def read_issues(folder):
    issues = []
    for f in sorted((folder / "issues").glob("*.md")):
        text = f.read_text(encoding="utf-8")
        m = re.match(r"(\d+)", f.name)
        title = re.search(r"^#\s+(.+)$", text, re.M)
        blocked = field(text, "**Blocked by:**") or ""
        issues.append({"n": int(m.group(1)) if m else len(issues) + 1,
                       "title": title.group(1).strip() if title else f.stem,
                       "status": (field(text, "**Status:**") or "").strip("` "),
                       "blockedBy": [int(x) for x in re.findall(r"\d+", blocked)]})
    return issues


# --- pull requests ---------------------------------------------------------------------------

PR_URL_RE = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/\d+")
PR_TTL = 20  # seconds; the ticket view polls, gh is slow and rate-limited
_pr_cache = {}
_pr_lock = threading.Lock()


def ticket_pr_urls(card_lines, session_tree, branch, project_dir):
    """PR links of a ticket: `PR <url>` lines on the card (/send adds one), PRs the ticket's
    sessions opened, and PRs whose head is the ticket's branch."""
    urls = []
    for line in card_lines:
        urls += PR_URL_RE.findall(line)

    def walk(nodes):
        for n in nodes:
            urls.extend(n.get("prs") or [])
            walk(n.get("children") or [])
    walk(session_tree)
    if branch and project_dir:
        code, origin = run(["git", "-C", project_dir, "remote", "get-url", "origin"])
        m = re.search(r"github\.com[:/]([^/]+/[^/\s]+?)(?:\.git)?\s*$", origin) if code == 0 else None
        if m:
            urls += branch_pr_urls(m.group(1), branch)
    return list(dict.fromkeys(urls))


def branch_pr_urls(repo, branch):
    key = "list:{}:{}".format(repo, branch)
    with _pr_lock:
        hit = _pr_cache.get(key)
        if hit and time.time() - hit[0] < PR_TTL:
            return hit[1]
    code, out = run(["gh", "pr", "list", "-R", repo, "--head", branch, "--state", "all", "--json", "url"])
    if code != 0:
        raise ApiError(502, "gh pr list: " + out.strip())
    urls = [p["url"] for p in json.loads(out)]
    with _pr_lock:
        _pr_cache[key] = (time.time(), urls)
    return urls


def checks_summary(rollup):
    """statusCheckRollup → counts: passed | failed | pending (skipped and neutral count as passed)."""
    out = {"passed": 0, "failed": 0, "pending": 0}
    for c in rollup or []:
        if c.get("__typename") == "StatusContext":
            st = (c.get("state") or "").upper()
            key = "passed" if st == "SUCCESS" else "pending" if st in ("PENDING", "EXPECTED") else "failed"
        elif (c.get("status") or "").upper() != "COMPLETED":
            key = "pending"
        else:
            key = "passed" if (c.get("conclusion") or "").upper() in ("SUCCESS", "SKIPPED", "NEUTRAL") else "failed"
        out[key] += 1
    return out


def pr_status(url):
    with _pr_lock:
        hit = _pr_cache.get(url)
        if hit and time.time() - hit[0] < PR_TTL:
            return hit[1]
    code, out = run(["gh", "pr", "view", url, "--json",
                     "number,title,state,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,url"])
    if code != 0:
        raise ApiError(502, "gh pr view {}: {}".format(url, out.strip()))
    d = json.loads(out)
    pr = {"url": d["url"], "number": d["number"], "title": d["title"],
          "state": "draft" if d["isDraft"] and d["state"] == "OPEN" else d["state"].lower(),
          "review": (d.get("reviewDecision") or "").lower().replace("_", " "),
          "merge": (d.get("mergeStateStatus") or "").lower(), "checks": checks_summary(d.get("statusCheckRollup"))}
    with _pr_lock:
        _pr_cache[url] = (time.time(), pr)
    return pr


def with_pr_steps(steps, prs):
    """Once a PR exists, /send has run: every step up to it is done, then one `PR #n` step per PR,
    done when merged or closed, else now."""
    if not prs:
        return steps
    steps = [dict(s, state="done") for s in steps]
    for pr in prs:
        steps.append({"step": "PR #{} {}".format(pr["number"], pr["state"]),
                      "state": "done" if pr["state"] in ("merged", "closed") else "now"})
    return steps


def workflow(column, scratch, issues):
    """Steps of the ticket's route, each done | now | next | todo.
    Card in Done → every step done. /ticket is done once ticket.md exists. The route is the first
    `/skill` in `Next:`; a `Status:` starting with "blocked" puts a `blocked: <reason>` step before
    it. With build issues the route is done and each issue is a step: done by its Status, now when
    on the frontier (every blocker done), else todo. Then /code-review and /send. The first todo
    after the last now (or after the last done) becomes next; without ticket.md nothing is next."""
    steps = [{"step": "/ticket", "state": "done" if scratch else "now"}]
    route = None
    if scratch:
        m = re.search(r"/[\w-]+", scratch.get("next") or "")
        route = m.group(0) if m else None
        status = scratch.get("status") or ""
        if status.lower().startswith("blocked"):
            reason = re.sub(r"^blocked\s*[:(]?\s*|\)$", "", status, flags=re.I).strip()
            steps.append({"step": "blocked: " + (reason or status), "state": "now"})
            if route:
                steps.append({"step": route, "state": "todo"})
        elif issues:
            if route:
                steps.append({"step": route, "state": "done"})
            done = {i["n"] for i in issues if i["status"].lower() == "done"}
            for i in issues:
                if i["n"] in done:
                    state = "done"
                elif all(b in done for b in i["blockedBy"]):
                    state = "now"
                else:
                    state = "todo"
                steps.append({"step": "#{} {}".format(i["n"], i["title"]), "state": state})
        elif route:
            steps.append({"step": route, "state": "now"})
    rest_now = scratch and not any(s["state"] == "now" for s in steps)
    steps.append({"step": "/code-review", "state": "now" if rest_now else "todo"})
    steps.append({"step": "/send", "state": "todo"})
    if column == "done":
        return [dict(s, state="done") for s in steps]
    if not scratch:
        return steps  # the route is unknown until /ticket ran, so nothing is next
    last = max(i for i, s in enumerate(steps) if s["state"] in ("now", "done"))
    for s in steps[last + 1:]:
        if s["state"] == "todo":
            s["state"] = "next"
            break
    return steps


def adf_lines(node):
    """Plain text lines of a Jira ADF description."""
    lines = []

    def text(n):
        return n.get("text", "") + "".join(text(c) for c in n.get("content", []) or [])

    for block in (node or {}).get("content", []) or []:
        t = text(block).strip()
        if t:
            lines.append(t)
    return lines


def ticket_view(project, ticket_id):
    info = lookup(project)
    d = info.get("dir")
    if not d or d == "none":
        raise ApiError(404, "project {}: no folder ({})".format(project, info.get("reason", "lookup failed")))
    ticket_id = ticket_id.upper()
    if info.get("board") == "vault":
        cards = parse_board(Path(info["board-file"]).read_text(encoding="utf-8"))
        card = next((c for c in cards if c["id"] == ticket_id), None)
        if not card:
            raise ApiError(404, "{} is not on {}".format(ticket_id, info["board-file"]))
        title, column, lines = card["title"], card["column"], card["lines"]
    elif jira_key(info):
        code, out = run(["acli", "jira", "workitem", "view", ticket_id, "--fields", "summary,status,description",
                         "--json"])
        if code != 0:
            raise ApiError(502, "Jira: " + out.strip())
        f = json.loads(out)["fields"]
        title, column = f.get("summary", ""), (f.get("status") or {}).get("name", "")
        lines = [title] + adf_lines(f.get("description"))
        if (f.get("status") or {}).get("statusCategory", {}).get("key") == "done":
            column = "done"
    else:
        raise ApiError(404, "project {} has no board".format(project))
    scratch, issues = None, []
    folders = sorted(Path(d, ".scratch").glob(ticket_id + "-*/ticket.md"))
    if folders:
        text = folders[0].read_text(encoding="utf-8")
        scratch = {"path": str(folders[0]), "branch": field(text, "branch:"), "status": field(text, "Status:"),
                   "next": field(text, "Next:")}
        issues = read_issues(folders[0].parent)
    handoff = Path(d, ".handoffs", "HANDOFF-{}.md".format(ticket_id))
    sessions = ticket_sessions(ticket_id, d, load_sessions())
    prs = [pr_status(u) for u in ticket_pr_urls(lines, sessions, (scratch or {}).get("branch"), d)]
    return {"id": ticket_id, "title": title, "column": column, "goal": card_goal(lines[1:]), "card": lines,
            "scratch": scratch,
            "handoff": str(handoff) if handoff.is_file() else None, "issues": issues,
            "workflow": with_pr_steps(workflow(column, scratch, issues), prs),
            "sessions": sessions, "prs": prs}


# --- weather ---------------------------------------------------------------------------------

WMO = {0: "Klar", 1: "Überwiegend klar", 2: "Leicht bewölkt", 3: "Bedeckt", 45: "Nebel", 48: "Nebel mit Reif",
       51: "Leichter Nieselregen", 53: "Nieselregen", 55: "Starker Nieselregen", 56: "Gefrierender Nieselregen",
       57: "Gefrierender Nieselregen", 61: "Leichter Regen", 63: "Regen", 65: "Starker Regen",
       66: "Gefrierender Regen", 67: "Gefrierender Regen", 71: "Leichter Schnee", 73: "Schnee", 75: "Starker Schnee",
       77: "Schneegriesel", 80: "Leichte Schauer", 81: "Schauer", 82: "Starke Schauer", 85: "Schneeschauer",
       86: "Starke Schneeschauer", 95: "Gewitter", 96: "Gewitter mit Hagel", 99: "Gewitter mit Hagel"}


def wmo_text(code):
    return WMO.get(code, "Unbekannt ({})".format(code))


WEATHER_URL = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode({
    "latitude": 50.9375, "longitude": 6.9603, "timezone": "Europe/Berlin", "forecast_days": 5,
    "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation,is_day",
    "hourly": "temperature_2m,weather_code,precipitation_probability",
    "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"})
WEATHER_TTL_MS = 10 * 60 * 1000
_weather = {"data": None}
_weather_lock = threading.Lock()


def shape_weather(raw, fetched_at):
    c, h, d = raw["current"], raw["hourly"], raw["daily"]
    hour = c["time"][:13]  # local "YYYY-MM-DDTHH"
    start = next(i for i, t in enumerate(h["time"]) if t[:13] >= hour)
    hours = [{"time": h["time"][i], "temp": h["temperature_2m"][i], "code": h["weather_code"][i],
              "precipProb": h["precipitation_probability"][i]} for i in range(start, min(start + 12, len(h["time"])))]
    today = c["time"][:10]
    t = d["time"].index(today)
    return {"place": "Köln",
            "current": {"temp": c["temperature_2m"], "apparentTemp": c["apparent_temperature"],
                        "code": c["weather_code"], "text": wmo_text(c["weather_code"]),
                        "windKmh": c["wind_speed_10m"], "precipMm": c["precipitation"], "isDay": bool(c["is_day"])},
            "today": {"min": d["temperature_2m_min"][t], "max": d["temperature_2m_max"][t],
                      "precipProbMax": d["precipitation_probability_max"][t],
                      "sunrise": d["sunrise"][t], "sunset": d["sunset"][t]},
            "hours": hours,
            "daily": [{"date": d["time"][i], "min": d["temperature_2m_min"][i], "max": d["temperature_2m_max"][i],
                       "code": d["weather_code"][i]} for i in range(t + 1, min(t + 5, len(d["time"])))],
            "fetchedAt": fetched_at}


def weather():
    with _weather_lock:
        cached = _weather["data"]
        if cached and now_ms() - cached["fetchedAt"] < WEATHER_TTL_MS:
            return cached
        try:
            with urllib.request.urlopen(WEATHER_URL, timeout=10) as r:
                raw = json.loads(r.read().decode("utf-8"))
            _weather["data"] = shape_weather(raw, now_ms())
        except Exception as e:
            traceback.print_exc()
            raise ApiError(502, "weather: Open-Meteo failed: {}".format(e))
        return _weather["data"]


# --- actions ---------------------------------------------------------------------------------

def pbcopy(text):
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)


def open_session(session_id):
    if not any(s["sessionId"] == session_id for s in load_sessions()):
        raise ApiError(404, "no session " + str(session_id))
    subprocess.run(["open", LINK.format(session_id)], check=True)


def note_done(n):
    if not re.fullmatch(r"\d+", str(n)):
        raise ApiError(400, "n must be a note number")
    code, out = run(["bash", str(GATHER), "--done", str(n)])
    if code != 0 or out.startswith("error:"):
        raise ApiError(409, out.strip())
    return {"done": out.strip()}


# --- HTTP ------------------------------------------------------------------------------------

def need(body, *keys):
    for k in keys:
        if not body.get(k) and body.get(k) != 0:
            raise ApiError(400, "missing " + k)
    return [body[k] for k in keys]


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def handle_api(self, method):
        try:
            url = urllib.parse.urlparse(self.path)
            q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
            if method == "GET":
                if url.path == "/":
                    return self.send_index()
                route = GETS.get(url.path)
                if not route:
                    raise ApiError(404, "no route " + url.path)
                return self.send_json(200, route(q))
            route = POSTS.get(url.path)
            if not route:
                raise ApiError(404, "no route " + url.path)
            n = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                raise ApiError(400, "body is not JSON")
            if not isinstance(body, dict):
                raise ApiError(400, "body must be a JSON object")
            return self.send_json(200, route(body))
        except ApiError as e:
            self.send_json(e.status, {"error": str(e)})
        except Exception as e:
            traceback.print_exc()
            self.send_json(500, {"error": "{}: {}".format(type(e).__name__, e)})

    def send_index(self):
        path = HERE / "index.html"
        if not path.is_file():
            raise ApiError(404, "index.html not found in " + str(HERE))
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.handle_api("GET")

    def do_POST(self):
        self.handle_api("POST")


def get_ticket(q):
    project, tid = q.get("project"), q.get("id")
    if not project or not tid:
        raise ApiError(400, "project and id are required")
    return ticket_view(project, tid)


def get_session(q):
    if not q.get("id"):
        raise ApiError(400, "id is required")
    return session_view(q["id"])


def post_reply(body):
    sid, text = need(body, "sessionId", "text")
    pbcopy(text)
    open_session(sid)
    return {"ok": True, "copied": True}


def post_open(body):
    open_session(need(body, "sessionId")[0])
    return {"ok": True}


def post_open_pr(body):
    url = need(body, "url")[0]
    if not PR_URL_RE.fullmatch(url):
        raise ApiError(400, "not a GitHub PR link: " + url)
    code, out = run(["open", url])
    if code != 0:
        raise ApiError(500, "open: " + out.strip())
    return {"ok": True}


def post_new_session(body):
    """Opens the Claude app's new Code session screen in the project's folder with the text
    prefilled (claude://code/new?q=…&folder=…); Quinn presses Enter there. A link can't pick the
    sidebar group."""
    project, text = need(body, "project", "text")
    d = lookup(project).get("dir", "none")
    if d == "none" or not Path(d).is_dir():
        raise ApiError(404, "no folder for project " + project)
    url = "claude://code/new?" + urllib.parse.urlencode({"q": text, "folder": d})
    code, out = run(["open", url])
    if code != 0:
        raise ApiError(500, "open: " + out.strip())
    return {"ok": True}


def post_copy(body):
    pbcopy(need(body, "text")[0])
    if body.get("app"):
        subprocess.run(["open", "-a", "Claude"], check=True)
    return {"ok": True}


GETS = {"/api/briefing": lambda q: BRIEFING.get(), "/api/projects": lambda q: projects_view(),
        "/api/ticket": get_ticket, "/api/session": get_session, "/api/weather": lambda q: weather(),
        "/api/order": lambda q: {"order": read_order()}}
POSTS = {"/api/briefing/refresh": lambda b: BRIEFING.start(), "/api/open": post_open, "/api/open-pr": post_open_pr, "/api/new-session": post_new_session, "/api/reply": post_reply,
         "/api/copy": post_copy, "/api/note-done": lambda b: note_done(need(b, "n")[0]),
         "/api/order": save_order}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=4777)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    # A server killed mid-run leaves its state copy behind; only one server runs, so any copy is stale.
    for stale in Path(tempfile.gettempdir()).glob("dashboard-briefing-*"):
        shutil.rmtree(stale)
    BRIEFING.start()
    print("dashboard on http://127.0.0.1:{}".format(args.port), file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
