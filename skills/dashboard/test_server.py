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

    def test_home_lists_in_progress_before_to_do(self):
        # A claimed ticket must stay on the home screen, or its sessions can't be reached.
        home = server.home_vault(server.parse_board(BOARD))
        self.assertEqual([c["id"] for c in home], ["A-7", "A-3", "A-2", "A-4", "A-6"])

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
        steps = [{"step": "/work", "state": "done"}, {"step": "/send", "state": "todo"}]
        out = server.with_pr_steps(steps, [{"number": 3, "state": "open"}])
        self.assertEqual([s["state"] for s in out], ["done", "done", "now"])
        self.assertEqual(out[-1]["step"], "PR #3 open")
        self.assertEqual(server.with_pr_steps(steps, []), steps)


class FakeClaude:
    """Stands in for the claude CLI: records each call with its folder and answers from a queue."""

    def __init__(self, *replies):
        self.calls, self.replies = [], list(replies)

    def __call__(self, args, cwd=None):
        self.calls.append((list(args), cwd))
        return self.replies.pop(0)


class BackgroundStart(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        saved = server.claude, server.lookup
        self.addCleanup(lambda: (setattr(server, "claude", saved[0]), setattr(server, "lookup", saved[1])))
        server.lookup = lambda name: {"dir": self.dir} if name == "skills" else {"dir": "none"}

    def tearDown(self):
        self.tmp.cleanup()

    def listed(self, *sids):
        return 0, json.dumps([agent(sid, self.dir, "x", 1) for sid in sids])

    def test_starts_in_the_project_folder_with_the_text_verbatim(self):
        server.claude = fake = FakeClaude((0, "Starting background service…\nbackgrounded · 36e71ce8 · skills: /work SKL-1\n"),
                                          self.listed("11111111-0000", "36e71ce8-c057-46bc"))
        got = server.post_bg_session({"project": "skills", "text": "/work SKL-1\n"})
        self.assertEqual((got["id"], got["sessionId"]), ("36e71ce8", "36e71ce8-c057-46bc"))
        self.assertEqual(fake.calls[0], (["--bg", "--permission-mode", "auto", "-n", "skills: /work SKL-1", "/work SKL-1"], self.dir))

    def test_a_started_session_missing_from_the_list_is_an_api_error(self):
        server.claude = FakeClaude((0, "backgrounded · 36e71ce8 · x\n"), self.listed("11111111-0000"))
        with self.assertRaises(server.ApiError) as e:
            server.post_bg_session({"project": "skills", "text": "hi"})
        self.assertIn("36e71ce8", str(e.exception))

    def test_name_is_the_project_and_the_first_line_cut_to_48(self):
        server.claude = fake = FakeClaude((0, "backgrounded · aaaaaaa1 · x\n"), self.listed("aaaaaaa1-0"),
                                          (0, "backgrounded · aaaaaaa2 · x\n"), self.listed("aaaaaaa2-0"))
        server.post_bg_session({"project": "skills", "text": "fix the clock\nmore detail"})
        server.post_bg_session({"project": "skills", "text": "x" * 80})
        self.assertEqual(fake.calls[0][0][4], "skills: fix the clock")
        self.assertEqual(fake.calls[2][0][4], "skills: " + "x" * 47 + "…")

    def test_cli_failure_is_an_api_error_with_its_output(self):
        server.claude = FakeClaude((1, "error: not logged in\n"))
        with self.assertRaises(server.ApiError) as e:
            server.post_bg_session({"project": "skills", "text": "hi"})
        self.assertIn("error: not logged in", str(e.exception))
        server.claude = FakeClaude((0, "something unexpected\n"))
        with self.assertRaises(server.ApiError) as e:
            server.post_bg_session({"project": "skills", "text": "hi"})
        self.assertIn("something unexpected", str(e.exception))

    def test_unknown_project_starts_nothing(self):
        server.claude = fake = FakeClaude()
        with self.assertRaises(server.ApiError) as e:
            server.post_bg_session({"project": "nope", "text": "hi"})
        self.assertEqual(e.exception.status, 404)
        self.assertEqual(fake.calls, [])

    def test_app_link_start_is_gone(self):
        self.assertNotIn("/api/new-session", server.POSTS)
        self.assertIn("/api/open", server.POSTS)


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
        self.session("local_3", lines=[user("/work 2")])
        self.session("local_4", lines=[user("<command-message>work</command-message>\n"
                                            "<command-name>/work</command-name>\n<command-args>a-2</command-args>")])
        self.session("local_5", cwd=wt, title="Ticket", lines=[user("/work"), dict(user("go"), gitBranch="feature/A-2")])
        self.session("local_6", lines=[user("/work 23")])
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

    def test_states(self):
        self.session("local_1", title="A-2 running", lines=[user("go")])
        self.session("local_2", title="A-2 done", lines=[user("go"), assistant([{"type": "text", "text": "ok"}], stop="end_turn")])
        self.session("local_3", title="A-2 old", isArchived=True)
        self.session("local_4", title="A-3 other", lines=[user("go")])
        states = server.ticket_states("A-2", self.project, server.load_sessions(self.sessions), self.transcripts)
        self.assertEqual(states, {"running": 1, "waiting": 1, "blocked": 0, "archived": 1})

    def test_word_boundary(self):
        self.assertTrue(server.mentions("Grill BGH-2 x", "BGH-2"))
        self.assertTrue(server.mentions("feature/BGH-2", "BGH-2"))
        self.assertFalse(server.mentions("Grill BGH-23 x", "BGH-2"))
        self.assertFalse(server.mentions("XBGH-2", "BGH-2"))
        self.assertTrue(server.ticket_prompt_matches("/work 2 please", "BGH-2"))
        self.assertFalse(server.ticket_prompt_matches("/work 23", "BGH-2"))
        self.assertFalse(server.ticket_prompt_matches("/work OBO-2", "BGH-2"))
        self.assertTrue(server.ticket_prompt_matches("/ticket BGH-2", "BGH-2"))  # sessions from before the rename
        self.assertFalse(server.ticket_prompt_matches("/ticket fix BGH-2 login", "BGH-2"))


def agent(sid, cwd, name, started, **fields):
    """One entry of `claude agents --json --all` as Claude Code 2.1.323 prints it."""
    a = {"pid": 31544, "id": sid[:8], "cwd": cwd, "kind": "background", "startedAt": started,
         "sessionId": sid, "name": name, "status": "idle", "state": "done"}
    a.update(fields)
    return {k: v for k, v in a.items() if v is not None}


class BackgroundFixture(Fixture):
    """A fake CLI whose `agents --json --all` lists self.agents, and transcripts for them."""

    def setUp(self):
        super().setUp()
        saved = server.claude, server.lookup, server.SESSIONS_DIR, server.TRANSCRIPTS_DIR
        self.addCleanup(lambda: (setattr(server, "claude", saved[0]), setattr(server, "lookup", saved[1]),
                                 setattr(server, "SESSIONS_DIR", saved[2]), setattr(server, "TRANSCRIPTS_DIR", saved[3])))
        server.SESSIONS_DIR, server.TRANSCRIPTS_DIR = self.sessions, self.transcripts
        board = Path(self.tmp.name, "board.md")
        board.write_text("## In progress\n\n- [ ] **A-2 · Do it**\n")
        server.lookup = lambda name: {"dir": self.project, "board": "vault", "board-file": str(board)}
        self.agents = []
        server.claude = self.fake_cli

    def fake_cli(self, args, cwd=None):
        if args == ["agents", "--json", "--all"]:
            return 0, json.dumps(self.agents)
        raise AssertionError("unexpected claude call: {}".format(args))

    def bg(self, sid, name, started, cwd=None, lines=None, **fields):
        cwd = cwd or self.project
        self.agents.append(agent(sid, cwd, name, started, **fields))
        if lines is not None:
            t = self.transcripts / server.re.sub(r"[^A-Za-z0-9]", "-", cwd) / (sid + ".jsonl")
            t.parent.mkdir(parents=True, exist_ok=True)
            t.write_text("".join(json.dumps(l) + "\n" for l in lines))
            return t


class BackgroundSessions(BackgroundFixture):
    """Background sessions come from `claude agents --json --all` and join a ticket by the same rules as app sessions."""

    def test_ticket_view_lists_matching_background_sessions_after_app_sessions(self):
        self.session("local_1", title="A-2 app")
        self.bg("bbbbbbbb-2", "skills: /work 2", 300, lines=[user("/work 2")])
        self.bg("aaaaaaaa-1", "skills: fix A-2 login", 200)
        self.bg("cccccccc-3", "skills: go on", 100, lines=[dict(user("go"), gitBranch="feature/A-2")])
        self.bg("dddddddd-4", "skills: A-2 elsewhere", 50, cwd="/elsewhere")
        self.bg("eeeeeeee-5", "skills: other", 60, lines=[user("/work 23")])
        self.agents.append(dict(agent("ffffffff-6", self.project, "A-2 interactive", 10), kind="interactive"))
        tree = server.ticket_view("p", "A-2")["sessions"]
        self.assertEqual([(n["kind"], n["sessionId"]) for n in tree], [
            ("app", "local_1"), ("background", "cccccccc-3"), ("background", "aaaaaaaa-1"), ("background", "bbbbbbbb-2")])
        b = tree[2]
        self.assertEqual((b["id"], b["title"], b["children"], b["prs"], b["servers"]),
                         ("aaaaaaaa", "skills: fix A-2 login", [], [], []))
        self.assertEqual(b["lastActivityAt"], 200)  # no transcript yet: its start time
        t = self.transcripts / server.re.sub(r"[^A-Za-z0-9]", "-", self.project) / "bbbbbbbb-2.jsonl"
        self.assertEqual(tree[3]["lastActivityAt"], int(t.stat().st_mtime * 1000))

    def test_states_from_the_cli(self):
        self.bg("aaaaaaaa-1", "A-2 busy", 1, status="busy", state="running")
        self.bg("aaaaaaaa-2", "A-2 idle", 2, status="idle", state="done")
        self.bg("aaaaaaaa-3", "A-2 question", 3, status="waiting", waitingFor="input needed", state="blocked")
        self.bg("aaaaaaaa-4", "A-2 blocked busy", 4, status="busy", state="blocked")
        self.bg("aaaaaaaa-5", "A-2 waiting", 5, status="waiting", state="running")
        self.bg("aaaaaaaa-6", "A-2 exited", 6, pid=None, status=None, state="done")
        tree = server.ticket_view("p", "A-2")["sessions"]
        self.assertEqual([(n["title"], n["state"]) for n in tree], [
            ("A-2 busy", "running"), ("A-2 idle", "waiting"), ("A-2 question", "blocked"),
            ("A-2 blocked busy", "blocked"), ("A-2 waiting", "blocked"), ("A-2 exited", "waiting")])
        self.assertEqual([n["summary"] for n in tree],
                         ["", "", "needs you: input needed", "needs you", "needs you", ""])

    def test_session_endpoint_returns_brief_and_chat(self):
        self.bg("aaaaaaaa-1", "skills: fix it", 100, status="busy", state="running",
                lines=[user("fix it"), assistant([{"type": "text", "text": "On it."}])])
        got = server.GETS["/api/session"]({"id": "aaaaaaaa-1"})
        self.assertEqual((got["sessionId"], got["id"], got["kind"], got["title"], got["state"]),
                         ("aaaaaaaa-1", "aaaaaaaa", "background", "skills: fix it", "running"))
        self.assertEqual([(e["role"], e["text"]) for e in got["chat"]], [("user", "fix it"), ("assistant", "On it.")])

    def test_session_endpoint_without_transcript_has_an_empty_chat(self):
        self.bg("aaaaaaaa-1", "skills: just started", 100, status="busy", state="running")
        self.assertEqual(server.GETS["/api/session"]({"id": "aaaaaaaa-1"})["chat"], [])

    def test_session_endpoint_unknown_id_is_404(self):
        with self.assertRaises(server.ApiError) as e:
            server.GETS["/api/session"]({"id": "nope"})
        self.assertEqual(e.exception.status, 404)
        with self.assertRaises(server.ApiError) as e:
            server.GETS["/api/session"]({})
        self.assertEqual(e.exception.status, 400)

    def test_home_row_counts_include_background_sessions(self):
        self.session("local_1", title="A-2 app running", lines=[user("go")])
        self.session("local_2", title="A-2 app archived", isArchived=True)
        self.bg("aaaaaaaa-1", "A-2 busy", 1, status="busy", state="running")
        self.bg("aaaaaaaa-2", "A-2 idle", 2)
        self.bg("aaaaaaaa-3", "A-2 question", 3, status="waiting", waitingFor="input needed", state="blocked")
        self.bg("aaaaaaaa-4", "no ticket", 4, status="busy", state="running")
        sessions = server.load_sessions() + server.background_sessions()
        view = server.project_view("p", {"status": "running"}, sessions)
        self.assertEqual(view["next"][0]["sessionCounts"], {"running": 2, "waiting": 1, "blocked": 1, "archived": 1})
        self.assertEqual((view["running"], view["background"]), (3, 2))


class TicketlessSessions(BackgroundFixture):
    """Home lists a project's background sessions that belong to no ticket on its board under the prompt box."""

    def test_background_sessions_matching_no_board_ticket_newest_first(self):
        Path(self.tmp.name, "board.md").write_text(
            "## In progress\n\n- [ ] **A-2 · Do it**\n\n## Done\n\n- [x] **A-1 · Did it**\n")
        self.session("local_1", title="app, no ticket")
        self.bg("aaaaaaaa-1", "skills: what is X?", 100, status="busy", state="running")
        self.bg("bbbbbbbb-2", "skills: /work 2", 200, lines=[user("/work 2")])
        self.bg("cccccccc-3", "skills: A-1 follow-up", 300)
        self.bg("dddddddd-4", "skills: elsewhere", 400, cwd="/elsewhere")
        self.bg("eeeeeeee-5", "skills: /ticket add a clock", 500, cwd=self.project + "/.claude/worktrees/x",
                lines=[user("/ticket add a clock")])
        sessions = server.load_sessions() + server.background_sessions()
        got = server.project_view("p", {"status": "running"}, sessions)["ticketless"]
        self.assertEqual([(s["sessionId"], s["id"], s["state"]) for s in got],
                         [("eeeeeeee-5", "eeeeeeee", "waiting"), ("aaaaaaaa-1", "aaaaaaaa", "running")])
        self.assertEqual(got[1]["lastActivityAt"], 100)

    def test_no_folder_lists_none(self):
        server.lookup = lambda name: {"dir": "none", "reason": "gone"}
        self.bg("aaaaaaaa-1", "skills: hi", 100)
        view = server.project_view("p", {"status": "running"}, server.background_sessions())
        self.assertEqual(view["ticketless"], [])


class SessionRemoval(BackgroundFixture):
    """Removing a background session stops its dev servers first, then the session, then `claude rm`."""

    def setUp(self):
        super().setUp()
        f = Path(self.project, ".claude", "launch.json")
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps({"configurations": [{"name": "web", "port": 5173}]}))
        self.procs = {5173: (11, self.project)}
        self.events, self.rm_reply = [], (0, "")

    def listen(self, port):
        return [self.procs[port]] if port in self.procs else []

    def kill(self, pid, sig):
        self.events.append(("kill", pid, sig))

    def fake_cli(self, args, cwd=None):
        if args[0] in ("stop", "rm"):
            self.events.append((args[0], args[1]))
            if args[0] == "rm" and self.rm_reply[0] == 0:
                self.agents = [a for a in self.agents if a["id"] != args[1]]
            return self.rm_reply if args[0] == "rm" else (0, "")
        return super().fake_cli(args, cwd)

    def remove(self, sid):
        return server.post_session_remove({"sessionId": sid}, listen=self.listen, kill=self.kill)

    def test_stops_its_servers_then_the_session_then_removes_it(self):
        self.bg("aaaaaaaa-1", "A-2 idle", 1, status="idle")
        self.assertEqual(self.remove("aaaaaaaa-1"), {"ok": True})
        self.assertEqual(self.events, [("kill", 11, server.signal.SIGTERM), ("stop", "aaaaaaaa"), ("rm", "aaaaaaaa")])
        self.assertEqual(server.background_sessions(), [])

    def test_an_exited_session_is_removed_without_stopping_it(self):
        self.bg("aaaaaaaa-1", "A-2 exited", 1, pid=None, status=None)
        self.remove("aaaaaaaa-1")
        self.assertEqual(self.events, [("kill", 11, server.signal.SIGTERM), ("rm", "aaaaaaaa")])

    def test_spares_a_server_another_listed_session_has(self):
        self.bg("aaaaaaaa-1", "A-2 idle", 1)
        self.bg("bbbbbbbb-2", "other in the same folder", 2, pid=None, status=None)
        self.remove("aaaaaaaa-1")
        self.assertEqual(self.events, [("stop", "aaaaaaaa"), ("rm", "aaaaaaaa")])

    def test_an_archived_app_session_does_not_spare_a_server(self):
        self.bg("aaaaaaaa-1", "A-2 idle", 1)
        self.session("local_1", isArchived=True)
        self.remove("aaaaaaaa-1")
        self.assertEqual(self.events[0], ("kill", 11, server.signal.SIGTERM))

    def test_rm_refusal_is_409_with_its_message_and_the_session_stays(self):
        self.bg("aaaaaaaa-1", "A-2 idle", 1)
        self.rm_reply = (1, "Not removed: worktree skl-22 has 2 unpushed commits\n")
        with self.assertRaises(server.ApiError) as e:
            self.remove("aaaaaaaa-1")
        self.assertEqual(e.exception.status, 409)
        self.assertIn("2 unpushed commits", str(e.exception))
        self.assertEqual([s["id"] for s in server.background_sessions()], ["aaaaaaaa"])

    def test_unknown_session_is_404_and_stops_nothing(self):
        with self.assertRaises(server.ApiError) as e:
            self.remove("nope")
        self.assertEqual(e.exception.status, 404)
        self.assertEqual(self.events, [])
        self.assertIn("/api/session/remove", server.POSTS)

    def test_reaper_keeps_a_server_a_background_session_lists(self):
        self.session("local_1", isArchived=True)
        self.bg("aaaaaaaa-1", "same folder", 1)
        self.assertEqual(server.reap_once(listen=self.listen, kill=self.kill), [])
        self.agents = []
        self.assertEqual([x["pid"] for x in server.reap_once(listen=self.listen, kill=self.kill)], [11])


class Chat(Fixture):
    """The session view's chat: prompts, replies and one line per tool call, read from the transcript."""

    def chat(self, lines):
        self.session("local_1", lines=lines)
        return server.session_chat(server.transcript_path(server.load_sessions(self.sessions)[0], self.transcripts))

    def test_prompts_replies_and_tool_calls_in_order(self):
        def at(e, t):
            return dict(e, timestamp=t)
        got = self.chat([
            at(user("look at the skills project"), "2026-10-16T15:28:29.958Z"),
            at(assistant([{"type": "thinking", "thinking": "hmm"}]), "2026-10-16T15:28:31.000Z"),
            at(assistant([{"type": "text", "text": "Locating the project."}]), "2026-10-16T15:28:32.000Z"),
            at(assistant([{"type": "tool_use", "name": "Bash", "input": {"command": "ls -d ~/Projects/*skill*\n  cat x",
                                                                       "description": "List"}}]), "2026-10-16T15:28:33.000Z"),
            at(user([{"type": "tool_result", "content": "skills"}]), "2026-10-16T15:28:34.000Z"),
            at(user("<command-message>work</command-message>\n<command-name>/work</command-name>\n"
                    "<command-args>SKL-1</command-args>"), "2026-10-16T15:28:35.000Z"),
        ])
        self.assertEqual(got, [
            {"role": "user", "text": "look at the skills project", "at": "2026-10-16T15:28:29.958Z"},
            {"role": "assistant", "text": "Locating the project.", "at": "2026-10-16T15:28:32.000Z"},
            {"role": "tool", "text": "Bash: ls -d ~/Projects/*skill* cat x", "at": "2026-10-16T15:28:33.000Z"},
            {"role": "user", "text": "/work SKL-1", "at": "2026-10-16T15:28:35.000Z"},
        ])


    def test_side_threads_meta_and_system_lines_are_left_out(self):
        got = self.chat([
            user("go"),
            dict(user("sub-agent task"), isSidechain=True),
            dict(assistant([{"type": "text", "text": "sub-agent reply"}]), isSidechain=True),
            dict(user("Caveat: local command output"), isMeta=True),
            dict(type="system", subtype="compact_boundary", content="Conversation compacted", timestamp="t"),
            user("<system-reminder>hook output</system-reminder>"),
            assistant([{"type": "text", "text": "done"}], stop="end_turn"),
        ])
        self.assertEqual([(e["role"], e["text"]) for e in got], [("user", "go"), ("assistant", "done")])

    def test_tool_gist_is_one_line_of_at_most_120_chars(self):
        got = self.chat([
            assistant([{"type": "tool_use", "name": "Read", "input": {"file_path": "/a/b.py", "limit": 5}},
                       {"type": "tool_use", "name": "Grep", "input": {"pattern": "def x", "path": "/a"}},
                       {"type": "tool_use", "name": "Agent", "input": {"description": "Find it", "prompt": "long"}},
                       {"type": "tool_use", "name": "Bash", "input": {"command": "echo " + "y" * 200}},
                       {"type": "tool_use", "name": "TodoWrite", "input": {"todos": []}}]),
        ])
        self.assertEqual([e["text"] for e in got][:3], ["Read: /a/b.py", "Grep: def x", "Agent: Find it"])
        self.assertEqual(got[3]["text"], "Bash: " + ("echo " + "y" * 200)[:119] + "…")
        self.assertEqual(got[4]["text"], "TodoWrite")

    def test_reads_only_the_last_2_mb(self):
        big = "x" * (server.CHAT_TAIL // 2)
        got = self.chat([user("first " + big), user("second " + big), user("third")])
        self.assertEqual([e["text"][:6] for e in got], ["second", "third"])

class Transcript(Fixture):
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
            ("/work", "done"), ("blocked: BGH-104", "now"), ("/implement", "next"),
            ("/code-review", "todo"), ("/send", "todo")])

    def test_build_issues(self):
        scratch = {"status": "needs-triage", "next": "`/build` — big"}
        issues = [dict(n=1, title="a", status="done", blockedBy=[]), dict(n=2, title="b", status="", blockedBy=[1]),
                  dict(n=3, title="c", status="", blockedBy=[2])]
        self.assertEqual(self.states(server.workflow("in progress", scratch, issues)), [
            ("/work", "done"), ("/build", "done"), ("#1 a", "done"), ("#2 b", "now"), ("#3 c", "next"),
            ("/code-review", "todo"), ("/send", "todo")])

    def test_done_card_and_not_started(self):
        self.assertTrue(all(s["state"] == "done" for s in server.workflow("done", None, [])))
        self.assertEqual(self.states(server.workflow("to do", None, [])),
                         [("/work", "now"), ("/code-review", "todo"), ("/send", "todo")])


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


class Servers(Fixture):
    """A session's servers are its folder's launch.json entries whose port something listens on
    from inside the session's folder; they are stopped once the session is archived."""

    def setUp(self):
        super().setUp()
        self.wt = self.project + "/.claude/worktrees/x"
        self.launch(self.wt, {"name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "port": 5173},
                    {"name": "api", "port": 4780, "url": "http://localhost:4780/docs"})
        self.procs = {}  # port -> (pid, cwd)

    def launch(self, cwd, *configs):
        f = Path(cwd, ".claude", "launch.json")
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps({"version": "0.0.1", "configurations": list(configs)}))

    def listen(self, port):
        return [self.procs[port]] if port in self.procs else []

    def test_listed_while_a_launch_port_listens_from_the_session_folder(self):
        s = self.session("local_1", cwd=self.wt)
        self.procs = {5173: (11, self.wt + "/web"), 4780: (12, self.wt)}
        self.assertEqual(server.session_servers(s, listen=self.listen), [
            {"name": "web", "url": "http://localhost:5173/", "port": 5173, "pid": 11},
            {"name": "api", "url": "http://localhost:4780/docs", "port": 4780, "pid": 12}])
        self.procs = {}
        self.assertEqual(server.session_servers(s, listen=self.listen), [])

    def test_listener_from_another_folder_is_not_listed(self):
        s = self.session("local_1", cwd=self.wt)
        self.procs = {5173: (11, self.project), 4780: (12, self.project + "/.claude/worktrees/xy")}
        self.assertEqual(server.session_servers(s, listen=self.listen), [])

    def test_main_checkout_session_does_not_own_nested_worktree_servers(self):
        self.launch(self.project, {"name": "web", "port": 5173})
        s = self.session("local_1")
        self.procs = {5173: (11, self.wt)}
        self.assertEqual(server.session_servers(s, listen=self.listen), [])

    def test_never_lists_the_dashboard_itself(self):
        s = self.session("local_1", cwd=self.wt)
        self.procs = {4780: (server.os.getpid(), self.wt)}
        self.assertEqual(server.session_servers(s, listen=self.listen), [])

    def test_no_launch_json_means_no_servers(self):
        s = self.session("local_1")
        self.procs = {5173: (11, self.project)}
        self.assertEqual(server.session_servers(s, listen=self.listen), [])

    def test_broken_launch_json_gives_an_error_row(self):
        f = Path(self.wt, ".claude", "launch.json")
        s = self.session("local_1", cwd=self.wt)
        f.write_text("[1]")
        got = server.session_servers(s, listen=self.listen)
        self.assertEqual(len(got), 1)
        self.assertIn("not a list", got[0]["error"])
        f.write_text("{")
        self.assertIn(str(f), server.session_servers(s, listen=self.listen)[0]["error"])

    def test_entry_without_a_port_gives_an_error_row(self):
        self.launch(self.wt, {"name": "web"}, {"name": "api", "port": 4780})
        s = self.session("local_1", cwd=self.wt)
        self.procs = {4780: (12, self.wt)}
        got = server.session_servers(s, listen=self.listen)
        self.assertEqual(got[0]["name"], "web")
        self.assertIn("no port", got[0]["error"])
        self.assertEqual(got[1]["pid"], 12)

    def test_reap_stops_archived_unless_a_live_session_shares_it(self):
        other = self.project + "/.claude/worktrees/y"
        self.launch(other, {"name": "app", "port": 6000})
        self.session("local_1", cwd=self.wt, isArchived=True)
        self.session("local_2", cwd=other, isArchived=True)
        self.session("local_3", cwd=other)
        self.procs = {5173: (11, self.wt), 6000: (12, other)}
        killed = []
        stopped = server.reap_servers(server.load_sessions(self.sessions), listen=self.listen,
                                      kill=lambda pid, sig: killed.append(pid))
        self.assertEqual(killed, [11])
        self.assertEqual([x["url"] for x in stopped], ["http://localhost:5173/"])

    def test_picks_the_owned_listener_and_reports_lsof_failure(self):
        self.launch(self.wt, {"name": "web", "port": 5173})
        s = self.session("local_1", cwd=self.wt)
        got = server.session_servers(s, listen=lambda p: [(7, "/elsewhere"), (8, self.wt)])
        self.assertEqual(got[0]["pid"], 8)

        def broken(port):
            raise RuntimeError("lsof broke")
        self.assertEqual(server.session_servers(s, listen=broken), [{"name": "web", "error": "lsof broke"}])

    def test_local_url(self):
        self.assertEqual(server.local_port("http://localhost:5173/x"), 5173)
        self.assertEqual(server.local_port("http://app.localhost/"), 80)
        self.assertEqual(server.local_port("http://[::1]:8000"), 8000)
        self.assertIsNone(server.local_port("https://example.com:5173/"))
        self.assertIsNone(server.local_port("file:///etc/passwd"))


if __name__ == "__main__":
    unittest.main()
