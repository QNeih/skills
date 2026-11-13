#!/usr/bin/env python3
"""Trigger eval: does a skill fire for the prompts it should, and stay quiet for near misses?

Usage: tests/eval-triggers.py <skill> [--runs 3] [--model claude-opus-5-5] [--workers 6]
Reads tests/triggers/<skill>.json: [{"query": "...", "should_trigger": true}, ...].

Each run is `claude -p <query>` in a throwaway project that holds Quinn's installed
skills and ~/.claude/CLAUDE.md, with <skill> taken from this repo instead of the
installed copy, so edits to its description are measured before they are installed.
User settings, hooks and plugins are not loaded (--setting-sources project).
A run counts as triggered when the first tool call is Skill(<skill>). The run is
killed at the first tool call, before it executes, so nothing real is touched.
Costs tokens: about one short model turn per query and run.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOME_SKILLS = Path.home() / ".claude" / "skills"


def make_project(skill: str) -> Path:
    proj = Path(tempfile.mkdtemp(prefix="skills-trig."))
    dest = proj / ".claude" / "skills"
    dest.mkdir(parents=True)
    for d in HOME_SKILLS.iterdir():
        if d.name in (skill, "synced") or d.name.startswith(".") or not (d / "SKILL.md").exists():
            continue
        shutil.copytree(d, dest / d.name, symlinks=False)
    shutil.copytree(REPO / "skills" / skill, dest / skill)
    claude_md = Path.home() / ".claude" / "CLAUDE.md"
    if claude_md.exists():
        shutil.copy(claude_md, proj / "CLAUDE.md")
    return proj


def first_tool(query: str, proj: Path, model: str, timeout: int) -> tuple[str, str]:
    """(tool name, its input JSON) of the first tool call, or ("", "") for none."""
    cmd = ["claude", "-p", query, "--output-format", "stream-json", "--verbose",
           "--include-partial-messages", "--setting-sources", "project",
           "--no-session-persistence", "--model", model]
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    p = subprocess.Popen(cmd, cwd=proj, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, text=True)
    tool, args, start = None, "", time.time()
    try:
        for line in p.stdout:
            if time.time() - start > timeout:
                return ("timeout", "")
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("type") == "result":
                return ("", "")
            se = ev.get("event", {}) if ev.get("type") == "stream_event" else {}
            t = se.get("type")
            if t == "content_block_start" and se["content_block"].get("type") == "tool_use":
                tool, args = se["content_block"]["name"], ""
            elif t == "content_block_delta" and tool:
                args += se["delta"].get("partial_json", "")
            elif t == "content_block_stop" and tool:
                if tool == "ToolSearch":  # loading tool schemas is not a decision; wait for the next call
                    tool = None
                    continue
                return (tool, args)
        return ("", "")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skill")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=120)
    a = ap.parse_args()
    cases = json.loads((REPO / "tests" / "triggers" / f"{a.skill}.json").read_text())
    proj = make_project(a.skill)
    try:
        jobs = [(i, c["query"]) for i, c in enumerate(cases) for _ in range(a.runs)]
        with ThreadPoolExecutor(a.workers) as ex:
            res = list(ex.map(lambda j: (j[0], first_tool(j[1], proj, a.model, a.timeout)), jobs))
    finally:
        shutil.rmtree(proj, ignore_errors=True)
    hits = {i: [] for i in range(len(cases))}
    for i, (tool, args) in res:
        fired = tool == "Skill" and json.loads(args or "{}").get("skill") == a.skill
        hits[i].append((fired, tool if not fired else ""))
    ok = 0
    for i, c in enumerate(cases):
        n = sum(f for f, _ in hits[i])
        good = (n / a.runs >= 0.5) == c["should_trigger"]
        ok += good
        other = ",".join(sorted({t for _, t in hits[i] if t})) or "-"
        print(f"{'ok  ' if good else 'MISS'} {n}/{a.runs} want={'yes' if c['should_trigger'] else 'no '} "
              f"other={other:<16} {c['query'][:90]}")
    print(f"{a.skill}: {ok}/{len(cases)} correct ({a.model}, {a.runs} runs each)")
    sys.exit(0 if ok == len(cases) else 1)


if __name__ == "__main__":
    main()
