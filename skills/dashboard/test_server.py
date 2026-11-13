#!/usr/bin/env python3
"""Checks for server.py on small fixtures: python3 test_server.py"""
import json
import os
import tempfile
import time
import unittest
from pathlib import Path

import server

BOARD = """---

kanban-plugin: board

---

## To do

- [ ] **A-1 · Blocked card**
\tBraucht: A-9, A-5
- [ ] **A-2 · Plain card**
\tBraucht: nichts
- [ ] **A-3 · Urgent card** #urgent
\tNeeds: A-5
- [ ] **A-4 · Fourth**
- [ ] **A-6 · Fifth**


## In Progress

- [ ] **A-7 · Working on it**
\tBranch `feature/A-7`


## Done

**Complete**
- [x] **A-5 · Finished**
"""


class Board(unittest.TestCase):
    def test_columns_and_blocks(self):
        cards = server.parse_board(BOARD)
        self.assertEqual([c["id"] for c in cards], ["A-1", "A-2", "A-3", "A-4", "A-6", "A-7", "A-5"])
        by = {c["id"]: c for c in cards}
        self.assertEqual(by["A-7"]["column"], "in progress")
        self.assertEqual(by["A-7"]["lines"][-1], "Branch `feature/A-7`")
        self.assertEqual(server.blocked_by(by["A-1"], cards), ["A-9"])
        self.assertEqual(server.blocked_by(by["A-3"], cards), [])

    def test_rank_urgent_first_then_board_order_without_blocked(self):
        ranked = server.rank_vault(server.parse_board(BOARD))
        self.assertEqual([c["id"] for c in ranked], ["A-3", "A-2", "A-4", "A-6"])

    def test_rank_jira(self):
        def issue(key, prio=3, typ="Task", cat="new", title="x", labels=()):
            return dict(id=key, title=title, column="", cat=cat, type=typ, prio=prio, labels=list(labels))
        ranked = server.rank_jira([issue("J-1"), issue("J-2", typ="Bug"), issue("J-3", prio=2),
                                   issue("J-4", title="Hotfix login"), issue("J-5", cat="indeterminate")])
        self.assertEqual([i["id"] for i in ranked], ["J-4", "J-3", "J-2", "J-5", "J-1"])


class Goal(unittest.TestCase):
    def test_goal_line_wins(self):
        self.assertEqual(server.card_goal(["Long text. More.", "Goal: Ship it"]), "Ship it")

    def test_first_sentence_skipping_meta(self):
        self.assertEqual(server.card_goal(["Branch `x`", "Save reports. Then share.", "Braucht: nichts"]), "Save reports.")

    def test_no_description(self):
        self.assertEqual(server.card_goal(["Braucht: BGH-1"]), "")


class PullRequests(unittest.TestCase):
    def test_checks_summary(self):
        rollup = [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"},
                  {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SKIPPED"},
                  {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FAILURE"},
                  {"__typename": "CheckRun", "status": "IN_PROGRESS"},
                  {"__typename": "StatusContext", "state": "PENDING"}]
        self.assertEqual(server.checks_summary(rollup), {"passed": 2, "failed": 1, "pending": 2})

    def test_pr_urls_from_card_and_sessions(self):
        card = ["SKL-15 · x", "PR https://github.com/o/r/pull/3"]
        tree = [{"prs": ["https://github.com/o/r/pull/3"], "children": [{"prs": ["https://github.com/o/r/pull/4"]}]}]
        self.assertEqual(server.ticket_pr_urls(card, tree, None, None),
                         ["https://github.com/o/r/pull/3", "https://github.com/o/r/pull/4"])

    def test_pr_steps(self):
        steps = [{"step": "/ticket", "state": "done"}, {"step": "/send", "state": "todo"}]
        out = server.with_pr_steps(steps, [{"number": 3, "state": "open"}])
        self.assertEqual([s["state"] for s in out], ["done", "done", "now"])
        self.assertEqual(out[-1]["step"], "PR #3 open")
        self.assertEqual(server.with_pr_steps(steps, []), steps)


class NewSession(unittest.TestCase):
    def test_command_becomes_request(self):
        self.assertEqual(server.as_request("/ticket SKL-15"),
                         "Run /ticket SKL-15: read ~/.claude/skills/ticket/SKILL.md and follow it.")
        self.assertEqual(server.as_request("hello"), "hello")


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.sessions, self.transcripts = root / "sessions", root / "projects"
        self.project = str(root / "Proj")

    def tearDown(self):
        self.tmp.cleanup()

    def session(self, sid, cwd=None, lines=(), **fields):
        cwd = cwd or self.project
        d = dict(sessionId=sid, cliSessionId="cli-" + sid, cwd=cwd, originCwd=cwd, title="Session", branch=None,
                 isArchived=False, createdAt=int(sid.split("_")[1]), lastActivityAt=0, spawnedFrom=None)
        d.update(fields)
        f = self.sessions / "a" / "b" / (sid + ".json")
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps(d))
        t = self.transcripts / server.re.sub(r"[^A-Za-z0-9]", "-", cwd) / ("cli-" + sid + ".jsonl")
        t.parent.mkdir(parents=True, exist_ok=True)
        t.write_text("".join(json.dumps(l) + "\n" for l in lines))
        return d


def user(text, **kw):
    return dict(type="user", message={"role": "user", "content": text}, timestamp="t", **kw)


def assistant(blocks, stop=None):
    return dict(type="assistant", message={"role": "assistant", "content": blocks, "stop_reason": stop}, timestamp="t")


class TicketSessions(Fixture):
    def test_matching_and_tree(self):
        wt = self.project + "/.claude/worktrees/x"
        self.session("local_1", title="Grill A-2 design")
        self.session("local_2", title="A-23 other ticket")
        self.session("local_3", lines=[user("/ticket 2")])
        self.session("local_4", lines=[user("<command-message>ticket</command-message>\n"
                                            "<command-name>/ticket</command-name>\n<command-args>a-2</command-args>")])
        self.session("local_5", cwd=wt, title="Ticket", lines=[user("/ticket"), dict(user("go"), gitBranch="feature/A-2")])
        self.session("local_6", lines=[user("/ticket 23")])
        self.session("local_7", title="Child", spawnedFrom={"sessionId": "local_1", "title": "Child", "name": "kid"})
        self.session("local_8", title="Grandchild", spawnedFrom={"sessionId": "local_7", "title": "Grandchild"})
        self.session("local_9", cwd="/elsewhere", title="A-2 elsewhere")
        self.session("local_10", title="Spawned A-2", spawnedFrom={"sessionId": "local_1", "title": "Spawned A-2"})
        all_sessions = server.load_sessions(self.sessions)
        tree = server.ticket_sessions("A-2", self.project, all_sessions, self.transcripts)
        self.assertEqual([n["sessionId"] for n in tree], ["local_1", "local_3", "local_4", "local_5"])
        kids = tree[0]["children"]
        self.assertEqual([k["sessionId"] for k in kids], ["local_7", "local_10"])
        self.assertEqual(kids[0]["children"][0]["sessionId"], "local_8")
        self.assertEqual(kids[0]["name"], "kid")
        self.assertEqual(tree[0]["link"], "claude://claude.ai/epitaxy/local_1")

    def test_word_boundary(self):
        self.assertTrue(server.mentions("Grill BGH-2 x", "BGH-2"))
        self.assertTrue(server.mentions("feature/BGH-2", "BGH-2"))
        self.assertFalse(server.mentions("Grill BGH-23 x", "BGH-2"))
        self.assertFalse(server.mentions("XBGH-2", "BGH-2"))
        self.assertTrue(server.ticket_prompt_matches("/ticket 2 please", "BGH-2"))
        self.assertFalse(server.ticket_prompt_matches("/ticket 23", "BGH-2"))
        self.assertFalse(server.ticket_prompt_matches("/ticket OBO-2", "BGH-2"))


class Transcript(Fixture):
    def test_parse(self):
        self.session("local_1", lines=[
            user("<system-reminder>ignore</system-reminder>"),
            user([{"type": "text", "text": "<system-reminder>x</system-reminder>"}, {"type": "text", "text": "hello"}]),
            user("Base directory for this skill: …", isMeta=True),
            user("<command-name>/goal</command-name>\n<command-args>ship it</command-args>"),
            assistant([{"type": "thinking", "thinking": "hmm"}, {"type": "text", "text": "Sure."}]),
            assistant([{"type": "tool_use", "name": "Bash", "input": {"command": "ls   -la\n/tmp", "description": "x"}}]),
            user([{"type": "tool_result", "content": "lots"}]),
            dict(assistant([{"type": "text", "text": "side"}]), isSidechain=True),
            assistant([{"type": "text", "text": "Done."}], stop="end_turn"),
        ])
        s = server.load_sessions(self.sessions)[0]
        msgs = server.parse_transcript(server.transcript_path(s, self.transcripts))
        self.assertEqual([(m["role"], m["text"]) for m in msgs], [
            ("user", "hello"), ("user", "/goal ship it"), ("assistant", "Sure."), ("tool", "▸ Bash ls -la /tmp"),
            ("assistant", "Done.")])
        self.assertEqual(server.parse_transcript(server.transcript_path(s, self.transcripts), limit=2)[0]["role"], "tool")

    def test_fallback_glob(self):
        self.session("local_1", lines=[user("hi")])
        s = dict(server.load_sessions(self.sessions)[0], cwd="/moved")
        self.assertIsNotNone(server.transcript_path(s, self.transcripts))

    def test_state(self):
        tool = assistant([{"type": "tool_use", "name": "Read", "input": {}}], stop="tool_use")
        self.session("local_1", lines=[user("go"), assistant([{"type": "text", "text": "ok"}], stop="end_turn")])
        self.session("local_2", lines=[user("go"), tool])
        self.session("local_3", lines=[user("go"), tool, user("[Request interrupted by user]")])
        self.session("local_4", lines=[user("go")], isArchived=True)
        state = {s["sessionId"]: server.session_state(s, self.transcripts) for s in server.load_sessions(self.sessions)}
        self.assertEqual(state, {"local_1": "waiting", "local_2": "running", "local_3": "waiting", "local_4": "archived"})
        stale = next(s for s in server.load_sessions(self.sessions) if s["sessionId"] == "local_2")
        later = server.now_ms() + server.RUNNING_STALE_MS + 1000
        self.assertEqual(server.session_state(stale, self.transcripts, now=later), "waiting")


class Workflow(unittest.TestCase):
    def states(self, steps):
        return [(s["step"], s["state"]) for s in steps]

    def test_blocked(self):
        scratch = {"status": "blocked (BGH-104)", "next": "`/implement` after BGH-104"}
        self.assertEqual(self.states(server.workflow("in progress", scratch, [])), [
            ("/ticket", "done"), ("blocked: BGH-104", "now"), ("/implement", "next"),
            ("/code-review", "todo"), ("/send", "todo")])

    def test_build_issues(self):
        scratch = {"status": "needs-triage", "next": "`/build` — big"}
        issues = [dict(n=1, title="a", status="done", blockedBy=[]), dict(n=2, title="b", status="", blockedBy=[1]),
                  dict(n=3, title="c", status="", blockedBy=[2])]
        self.assertEqual(self.states(server.workflow("in progress", scratch, issues)), [
            ("/ticket", "done"), ("/build", "done"), ("#1 a", "done"), ("#2 b", "now"), ("#3 c", "next"),
            ("/code-review", "todo"), ("/send", "todo")])

    def test_done_card_and_not_started(self):
        self.assertTrue(all(s["state"] == "done" for s in server.workflow("done", None, [])))
        self.assertEqual(self.states(server.workflow("to do", None, [])),
                         [("/ticket", "now"), ("/code-review", "todo"), ("/send", "todo")])


class Briefing(unittest.TestCase):
    def test_parse_gather_drops_did(self):
        out = ("today: 2026-11-13 Fri\nlast workday: 2026-11-12 Thu\nsince: 2026-11-12 00:00 (first run)\n"
               "# Today\nnote 1: call\n# P\nprompt 2026-11-12 10:00 x\ncommit 2026-11-12 11:00 y\n"
               "left off: main, clean\nnext: P-1 · t (to do)\nsentry o/p: 3 issues, new: P-4F2 P-4F3, regressed: P-3A1\n"
               "# Q\nleft off: main, clean\n")
        b = server.parse_gather(out)
        self.assertEqual(b["header"]["lastWorkday"], "2026-11-12 Thu")
        self.assertEqual(b["today"], ["note 1: call"])
        self.assertEqual([p["name"] for p in b["projects"]], ["P"])
        self.assertEqual([l["kind"] for l in b["projects"][0]["lines"]], ["next", "sentry"])
        self.assertEqual(server.sentry_ids(b["projects"][0]["lines"][1]["text"]), ["P-4F2", "P-4F3", "P-3A1"])

    def test_jumps(self):
        b = server.parse_gather("# P\nsentry o/p: 3 issues, new: P-4F2, regressed: P-3A1\n"
                                "dependabot: 1 new of 2 open: #4 Bump x\nnote 3: send offer\n")
        self.assertEqual(server.briefing_jumps("P", dict(b, status="running")), [])
        jumps = server.briefing_jumps("P", dict(b, status="ready"))
        self.assertEqual([(j["key"], j["action"], j["arg"]) for j in jumps], [
            ("s", "copy", "/sentry-fix P-4F2 P-3A1 P"), ("d", "copy", "/dependabot-review"), ("n", "note-done", "3")])

    def test_sort_projects(self):
        def v(name, act, nxt=()):
            return dict(name=name, lastActivityAt=act, next=list(nxt), jumps=[], error=None)
        views = [v("idle-recent", 30), v("old", 10, ["x"]), v("new", 20, ["x"]), v("never", None, ["x"])]
        self.assertEqual([p["name"] for p in server.sort_projects(views)], ["new", "old", "never", "idle-recent"])
        ordered = server.sort_projects(views, ["gone", "old", "idle-recent"])
        self.assertEqual([p["name"] for p in ordered], ["old", "idle-recent", "new", "never"])

    def test_save_and_read_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            orig = server.ORDER_FILE
            server.ORDER_FILE = Path(tmp) / "dashboard" / "order.json"
            try:
                self.assertEqual(server.read_order(), [])
                server.save_order({"order": ["B", "A"]})
                self.assertEqual(server.read_order(), ["B", "A"])
                self.assertEqual(os.listdir(str(server.ORDER_FILE.parent)), ["order.json"])
                with self.assertRaises(server.ApiError):
                    server.save_order({"order": "A"})
            finally:
                server.ORDER_FILE = orig


class Weather(unittest.TestCase):
    def test_codes(self):
        self.assertEqual(server.wmo_text(0), "Klar")
        self.assertEqual(server.wmo_text(2), "Leicht bewölkt")
        self.assertEqual(server.wmo_text(45), "Nebel")
        self.assertEqual(server.wmo_text(53), "Nieselregen")
        self.assertEqual(server.wmo_text(63), "Regen")
        self.assertEqual(server.wmo_text(73), "Schnee")
        self.assertEqual(server.wmo_text(81), "Schauer")
        self.assertEqual(server.wmo_text(95), "Gewitter")
        self.assertEqual(server.wmo_text(42), "Unbekannt (42)")
        for code in (0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86,
                     95, 96, 99):
            self.assertIn(code, server.WMO)

    def test_shape(self):
        hours = ["2026-11-13T{:02d}:00".format(h) for h in range(24)] + ["2026-11-14T00:00"]
        days = ["2026-11-1{}".format(d) for d in range(3, 8)]
        raw = {"current": {"time": "2026-11-13T03:45", "temperature_2m": 2.7, "apparent_temperature": -0.1,
                           "weather_code": 3, "wind_speed_10m": 5.4, "precipitation": 0.0, "is_day": 0},
               "hourly": {"time": hours, "temperature_2m": list(range(25)), "weather_code": [0] * 25,
                          "precipitation_probability": [5] * 25},
               "daily": {"time": days, "weather_code": [1, 2, 3, 61, 71], "temperature_2m_max": [9] * 5,
                         "temperature_2m_min": [2] * 5, "precipitation_probability_max": [8] * 5,
                         "sunrise": ["s"] * 5, "sunset": ["e"] * 5}}
        w = server.shape_weather(raw, 123)
        self.assertEqual(w["current"]["text"], "Bedeckt")
        self.assertFalse(w["current"]["isDay"])
        self.assertEqual([h["time"][11:13] for h in w["hours"]][:2], ["03", "04"])
        self.assertEqual(len(w["hours"]), 12)
        self.assertEqual([d["date"] for d in w["daily"]], days[1:])
        self.assertEqual(w["fetchedAt"], 123)


if __name__ == "__main__":
    unittest.main()
