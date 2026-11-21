#!/usr/bin/env python3
"""Starts the entries of a project's run file (.claude/launch.json) and waits for their ports.

  start.py ports <dir>   check each entry's port; prints one line per entry:
                           running: <name> port <p>         already listening from this folder
                           moved: <name> port <old> -> <new>  taken from another folder; launch.json changed
                           taken: <name> port <p>: <command>  a container port held by another program
                           start: <name>                    to be started
  start.py up <dir>      ports, then starts every `start:` entry detached, then wait
                           started: <name> pid <pid>, log <log>
  start.py wait <dir>    waits for every entry's port to listen from this folder, then prints
                           up: <name> port <p>
                           no answer: <name> port <p> after <s> s, then the log's last 20 lines
                           url: http://localhost:<p>        the first entry with a port, when it is up

A listener counts as this folder's when its working directory is inside <dir> but not in a ticket
worktree under it (<dir>/.claude/worktrees/). Docker publishes container ports from its own
process, so for a docker entry any Docker listener counts.
Logs: $TMPDIR/start-project/<project>-<entry>.log. Wait time: START_PROJECT_WAIT seconds (default 60).
A port move changes only numbers in launch.json, so /send can tell it from a real edit.
Exit 0 when every port is up, 1 on an error or a port without answer.
"""
import json
import os
import re
import subprocess
import sys
import time


def die(msg):
    print(f"error: {msg}")
    sys.exit(1)


def lsof(*args):
    r = subprocess.run(["lsof", "-nP", *args], capture_output=True, text=True)
    return r.stdout


def listeners(port):
    """(pid, cwd, command) of each process listening on the TCP port."""
    out = []
    for pid in sorted(set(lsof(f"-iTCP:{port}", "-sTCP:LISTEN", "-t").split())):
        cwd = next((l[1:] for l in lsof("-a", "-p", pid, "-d", "cwd", "-Fn").splitlines() if l.startswith("n")), "")
        cmd = subprocess.run(["ps", "-ww", "-o", "command=", "-p", pid], capture_output=True, text=True).stdout.strip()
        out.append((pid, cwd, cmd))
    return out


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

    def inside(self, cwd):
        wt = os.path.join(self.dir, ".claude", "worktrees") + "/"
        return (cwd == self.dir or cwd.startswith(self.dir + "/")) and not (cwd + "/").startswith(wt)

    @staticmethod
    def is_docker(entry):
        return os.path.basename(entry.get("runtimeExecutable", "")) in ("docker", "docker-compose")

    def ours(self, entry, held):
        docker = self.is_docker(entry)
        return any(self.inside(cwd) or (docker and re.search(r"docker|vpnkit|orbstack", cmd, re.I))
                   for _, cwd, cmd in held)

    def log(self, entry):
        d = os.path.join(os.environ.get("TMPDIR", "/tmp"), "start-project")
        os.makedirs(d, exist_ok=True)
        name = re.sub(r"[^\w.-]", "_", entry.get("name", "entry"))
        return os.path.join(d, f"{os.path.basename(self.dir)}-{name}.log")

    def move(self, entry, old):
        used = {e.get("port") for e in self.entries}
        new = old + 1
        while new in used or listeners(new):
            new += 1
        # whole numbers only: the port and every argument that names it
        self.text = re.sub(rf"(?<![\d.]){old}(?![\d.])", str(new), self.text)
        with open(self.file, "w") as f:
            f.write(self.text)
        self.entries = json.loads(self.text)["configurations"]
        return new

    def ports(self):
        """Prints each entry's state; returns the entries to start."""
        todo = []
        for i, entry in enumerate(self.entries):
            name, port = entry.get("name", f"entry {i + 1}"), entry.get("port")
            held = listeners(port) if port else []
            if not held:
                print(f"start: {name}")
                todo.append(i)
            elif self.ours(entry, held):
                print(f"running: {name} port {port}")
            elif self.is_docker(entry):
                print(f"taken: {name} port {port}: {held[0][2]}")
            else:
                new = self.move(entry, port)
                print(f"moved: {name} port {port} -> {new}")
                print(f"start: {name}")
                todo.append(i)
        return todo

    def start(self, i):
        entry = self.entries[i]
        name, log = entry.get("name", f"entry {i + 1}"), self.log(entry)
        cwd = os.path.join(self.dir, entry.get("cwd", ""))
        cmd = [entry.get("runtimeExecutable", "")] + list(entry.get("runtimeArgs") or [])
        try:
            with open(log, "w") as out:
                # a session of its own: the server outlives this script and the shell that ran it
                p = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=out,
                                     stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as e:
            print(f"error: {name}: cannot run {cmd[0]!r}: {e.strerror}")
            return False
        print(f"started: {name} pid {p.pid}, log {log}")
        return True

    def wait(self):
        limit = int(os.environ.get("START_PROJECT_WAIT", "60"))
        deadline = time.time() + limit
        # a container port another program holds was reported as `taken:`; it never becomes ours
        taken = {e["port"] for e in self.entries if e.get("port") and self.is_docker(e)
                 and (held := listeners(e["port"])) and not self.ours(e, held)}
        pending = [e for e in self.entries if e.get("port") and e["port"] not in taken]
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
            if not e.get("port") or e["port"] in taken:
                continue
            name = e.get("name", f"entry {i + 1}")
            if e["port"] in up:
                print(f"up: {name} port {e['port']}")
                continue
            ok = False
            print(f"no answer: {name} port {e['port']} after {limit} s")
            log = self.log(e)
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
