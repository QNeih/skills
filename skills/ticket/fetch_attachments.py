#!/usr/bin/env python3
"""Download every attachment of a Jira issue into a folder as <NN>-<sanitized-filename>.

Usage: fetch_attachments.py --site <url> --cloud-id <id> <KEY> <dir> [--max-mb 20]

The API token is read from the macOS Keychain item `jira-attachments`
(account = Jira login email) and never printed.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

KEYCHAIN_SERVICE = "jira-attachments"
SETUP_HINT = f"run: security add-generic-password -s {KEYCHAIN_SERVICE} -a <jira-email> -w"


def keychain_credentials() -> tuple[str, str]:
    item = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE],
                          capture_output=True, text=True)
    token = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                           capture_output=True, text=True)
    account = re.search(r'"acct"<blob>="([^"]+)"', item.stdout)
    if token.returncode or not account:
        sys.exit(f"error: Keychain item '{KEYCHAIN_SERVICE}' missing; {SETUP_HINT}")
    return account.group(1), token.stdout.strip()


def get(url: str, auth: str) -> bytes:
    request = urllib.request.Request(url, headers={"Authorization": f"Basic {auth}", "Accept": "application/json"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def fetch_issue(bases: list[str], key: str, auth: str, email: str) -> dict:
    # Jira answers 404, not 401, when it rejects the credentials.
    codes = []
    for base in bases:
        try:
            return json.loads(get(f"{base}/rest/api/3/issue/{key}?fields=attachment", auth))
        except urllib.error.HTTPError as e:
            codes.append(f"{e.code} from {base}")
    sys.exit(f"error: {', '.join(codes)}; key wrong, no access, or token rejected for {email} ({SETUP_HINT} -U)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", required=True)
    parser.add_argument("--cloud-id", required=True)
    parser.add_argument("key")
    parser.add_argument("dir", type=Path)
    parser.add_argument("--max-mb", type=float, default=20)
    args = parser.parse_args()

    email, token = keychain_credentials()
    auth = base64.b64encode(f"{email}:{token}".encode()).decode()
    # Classic API tokens work on the site URL, scoped tokens only through the API gateway.
    bases = [args.site.rstrip("/"), f"https://api.atlassian.com/ex/jira/{args.cloud_id}"]
    issue = fetch_issue(bases, args.key, auth, email)
    attachments = issue["fields"]["attachment"]
    print(f"{len(attachments)} attachment(s)")

    args.dir.mkdir(parents=True, exist_ok=True)
    for n, a in enumerate(attachments, 1):
        name = f"{n:02d}-" + re.sub(r"[^A-Za-z0-9._-]+", "-", a["filename"])
        size = f"{a['size'] / 1024:.0f} KB"
        if a["size"] > args.max_mb * 1024 * 1024:
            print(f"skipped {name}  {a['mimeType']}  {size}  (over {args.max_mb:g} MB, rerun with --max-mb)")
            continue
        (args.dir / name).write_bytes(get(a["content"], auth))
        print(f"saved   {args.dir / name}  {a['mimeType']}  {size}")


if __name__ == "__main__":
    main()
