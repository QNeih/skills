#!/usr/bin/env bash
# Project note lookup for /wiki: the note in <vault>/wiki/projects whose name matches NAME,
# ignoring case, spaces and hyphens. Prints `key: value` lines; always exits 0 so callers read the reason.
#   vault-lookup.sh --note NAME   project: <note name>, note: <path>  |  project: none, reason: …
# Env: VAULT (Obsidian vault).
set -u

# NFC, lowercase, spaces and hyphens removed
norm() { perl -CSA -MUnicode::Normalize -le '$_ = lc NFC shift; s/[ -]//g; print' "$1"; }

none() { echo "project: none"; echo "reason: $1"; exit 0; }

[ -n "${VAULT:-}" ] || none "VAULT must be set"
VAULT=$(cd "$VAULT" && pwd -P) || none "vault $VAULT not found"
[ "${1:-}" = --note ] && [ -n "${2:-}" ] || none "usage: vault-lookup.sh --note NAME"

want=$(norm "$2")
for n in "$VAULT"/wiki/projects/*.md; do
  case "$n" in *" Board.md") continue ;; esac
  [ -f "$n" ] || continue
  name=$(basename "$n" .md)
  if [ "$(norm "$name")" = "$want" ]; then echo "project: $name"; echo "note: $n"; exit 0; fi
done
none "no project note named $2"
