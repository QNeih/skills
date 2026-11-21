#!/usr/bin/env python3
"""Starts the entries of a project's run file (.claude/launch.json) and waits for their ports.

  start.py ports <dir>   decide per entry: already running, port moved, port taken, or to start
  start.py up <dir>      ports, then start the entries to start detached, then wait
  start.py wait <dir>    wait up to START_PROJECT_WAIT seconds (default 60) for every port

The output lines are described in SKILL.md. Exit 0 when every port is up, 1 on an error or a
port without answer.
"""
import collections
import json
import os
import re
import shutil
import subprocess
import sys
import time

Listener = collections.namedtuple("Listener", "pid cwd cmd")


def die(msg):
    print(f"error: {msg}")
    sys.exit(1)


def run(cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout
    except OSError:
        return ""


def cwd_of(pid):
    out = run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
    return next((l[1:] for l in out.splitlines() if l.startswith("n")), "")


def listeners(port):
    """Each process listening on the TCP port."""
    pids = sorted(set(run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"]).split()))
    return [Listener(pid, cwd_of(pid), run(["ps", "-ww", "-o", "command=", "-p", pid]).strip()) for pid in pids]


def closing(text, i):
    """Index of the bracket that closes the one at text[i], skipping JSON strings."""
    depth, in_str, esc = 0, False, False
    for j in range(i, len(text)):
        c = text[j]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth == 0:
                return j
    raise ValueError("unbalanced brackets")


def entry_spans(text):
    """(start, end) of each entry object in the configurations array."""
    m = re.search(r'"configurations"\s*:\s*\[', text)
    end, spans, i = closing(text, m.end() - 1), [], m.end()
    while i < end:
        if text[i] == "{":
            j = closing(text, i)
            spans.append((i, j + 1))
            i = j
        i += 1
    return spans


class Project:
    def __init__(self, path):
        self.dir = os.path.realpath(path)
        if not os.path.isdir(self.dir):
            die(f"folder {path} not found")
        self.file = os.path.join(self.dir, ".claude", "launch.json")
        if not os.path.isfile(self.file):
            die(f"no run file: {self.file}")
        with open(self.file) as f:
            self.text = f.read()
        try:
            self.entries = json.loads(self.text).get("configurations") or []
        except ValueError as e:
            die(f"{self.file} is not valid JSON: {e}")
        if not self.entries:
            die(f"no entries in {self.file}")
        self.taken = None  # ports of container entries another program holds

    def name(self, i):
        return self.entries[i].get("name", f"entry {i + 1}")

    def folder(self, entry):
        return os.path.realpath(os.path.join(self.dir, entry.get("cwd", "")))

    def inside(self, cwd):
        wt = os.path.join(self.dir, ".claude", "worktrees") + "/"
        return (cwd == self.dir or cwd.startswith(self.dir + "/")) and not (cwd + "/").startswith(wt)

    @staticmethod
    def is_docker(entry):
        return os.path.basename(entry.get("runtimeExecutable", "")) in ("docker", "docker-compose")

    def published(self, entry):
        """Host ports the entry's compose project publishes, by `docker compose ps`."""
        args = list(entry.get("runtimeArgs") or [])
        args = args[:args.index("up")] if "up" in args else args
        out = run([entry["runtimeExecutable"], *args, "ps", "--format", "json"], cwd=self.folder(entry)).strip()
        try:
            rows = json.loads(out) if out.startswith("[") else [json.loads(l) for l in out.splitlines() if l.strip()]
        except ValueError:
            return set()
        ports = set()
        for r in rows:
            ports |= {p.get("PublishedPort") for p in r.get("Publishers") or []}
            ports |= {int(p) for p in re.findall(r":(\d+)->", r.get("Ports", ""))}
        return ports

    def ours(self, entry, held):
        # Docker publishes container ports from its own process, so ask compose instead of the cwd
        if self.is_docker(entry):
            return bool(held) and entry["port"] in self.published(entry)
        return any(self.inside(l.cwd) for l in held)

    def running_pid(self, entry):
        """Pid of a process running the entry's command from the entry's folder, for an entry without a port."""
        exe = os.path.basename(entry.get("runtimeExecutable", "")).lower()
        tail = " ".join(entry.get("runtimeArgs") or [])
        folder = self.folder(entry)
        for line in run(["ps", "-axww", "-o", "pid=,command="]).splitlines():
            pid, _, cmd = line.strip().partition(" ")
            if tail and not cmd.endswith(" " + tail):
                continue
            head = cmd[: len(cmd) - len(tail)].split() if tail else cmd.split()[-1:]
            # python3 shows as .../Python, npm as `node .../npm`
            if not any(os.path.basename(t).lower().startswith(exe) or exe.startswith(os.path.basename(t).lower())
                       for t in head):
                continue
            if int(pid) != os.getpid() and cwd_of(pid) == folder:
                return pid
        return None

    def log(self, i):
        d = os.path.join(os.environ.get("TMPDIR", "/tmp"), "start-project")
        os.makedirs(d, exist_ok=True)
        entry = re.sub(r"[^\w.-]", "_", self.name(i))
        return os.path.join(d, f"{os.path.basename(self.dir)}-{entry}.log")

    def move(self, i, old):
        used = {e.get("port") for e in self.entries}
        new = old + 1
        while new in used or listeners(new):
            new += 1
        # only this entry's port value and its arguments, and only the number, so /send can restore the edit
        a, b = entry_spans(self.text)[i]
        entry = self.text[a:b]
        entry = re.sub(rf'("port"\s*:\s*){old}(?![\d.])', rf"\g<1>{new}", entry, count=1)
        m = re.search(r'"runtimeArgs"\s*:\s*\[', entry)
        if m:
            s, e = m.end() - 1, closing(entry, m.end() - 1)
            entry = entry[:s] + re.sub(rf"(?<![\d.]){old}(?![\d.])", str(new), entry[s:e]) + entry[e:]
        self.text = self.text[:a] + entry + self.text[b:]
        with open(self.file, "w") as f:
            f.write(self.text)
        self.entries = json.loads(self.text)["configurations"]
        return new

    def ports(self):
        """Prints each entry's state; returns the entries to start."""
        todo, self.taken = [], set()
        for i, entry in enumerate(self.entries):
            name, port = self.name(i), entry.get("port")
            if not port:
                pid = self.running_pid(entry)
                if pid:
                    print(f"running: {name} pid {pid}")
                else:
                    print(f"start: {name}")
                    todo.append(i)
                continue
            held = listeners(port)
            if not held:
                print(f"start: {name}")
                todo.append(i)
            elif self.ours(entry, held):
                print(f"running: {name} port {port}")
            elif self.is_docker(entry):
                self.taken.add(port)
                print(f"taken: {name} port {port}: {held[0].cmd}")
            else:
                new = self.move(i, port)
                print(f"moved: {name} port {port} -> {new}")
                print(f"start: {name}")
                todo.append(i)
        return todo

    def start(self, i):
        entry, name, log = self.entries[i], self.name(i), self.log(i)
        cmd = [entry.get("runtimeExecutable", "")] + list(entry.get("runtimeArgs") or [])
        try:
            with open(log, "w") as out:
                # a session of its own: the server outlives this script and the shell that ran it
                p = subprocess.Popen(cmd, cwd=self.folder(entry), stdin=subprocess.DEVNULL, stdout=out,
                                     stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as e:
            print(f"error: {name}: cannot run {cmd[0]!r}: {e.strerror}")
            return False
        print(f"started: {name} pid {p.pid}, log {log}")
        return True

    def wait(self):
        if self.taken is None:  # wait alone: `ports` ran in an earlier call
            self.taken = {e["port"] for e in self.entries if e.get("port") and self.is_docker(e)
                          and (held := listeners(e["port"])) and not self.ours(e, held)}
        limit = int(os.environ.get("START_PROJECT_WAIT", "60"))
        deadline = time.time() + limit
        pending = [e for e in self.entries if e.get("port") and e["port"] not in self.taken]
        up = set()
        while pending and time.time() < deadline:
            for e in list(pending):
                if self.ours(e, listeners(e["port"])):
                    up.add(e["port"])
                    pending.remove(e)
            if pending:
                time.sleep(0.5)
        ok = True
        for i, e in enumerate(self.entries):
            if not e.get("port") or e["port"] in self.taken:
                continue
            if e["port"] in up:
                print(f"up: {self.name(i)} port {e['port']}")
                continue
            ok = False
            print(f"no answer: {self.name(i)} port {e['port']} after {limit} s")
            log = self.log(i)
            if os.path.isfile(log):
                with open(log, errors="replace") as f:
                    tail = f.read().splitlines()[-20:]
                print(f"log {log}, last {len(tail)} lines:")
                for line in tail:
                    print(f"  {line}")
        first = next((e["port"] for e in self.entries if e.get("port")), None)
        if first in up:
            print(f"url: http://localhost:{first}")
        return ok


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("ports", "up", "wait"):
        die("usage: start.py ports|up|wait <dir>")
    if not shutil.which("lsof"):
        die("lsof not installed")
    cmd, project = sys.argv[1], Project(sys.argv[2])
    ok = True
    if cmd in ("ports", "up"):
        todo = project.ports()
        if cmd == "up":
            ok = all([project.start(i) for i in todo])
    if cmd in ("up", "wait"):
        ok = project.wait() and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
