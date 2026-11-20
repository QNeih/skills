#!/usr/bin/env bash
# Creates a project's wiki inside the brain.
#   wiki.sh VAULT PROJECT [REMOTE]
# Prints "created: DIR", "cloned: DIR" or "exists: DIR".
set -eu
vault=${1:?usage: wiki.sh VAULT PROJECT [REMOTE]}
project=${2:?usage: wiki.sh VAULT PROJECT [REMOTE]}
remote=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
dir="$vault/wiki/projects/$project"
ignore='wiki/projects/*/'

# The wiki is its own repo, so the brain leaves it out of its commits
touch "$vault/.gitignore"
if ! grep -qxF "$ignore" "$vault/.gitignore"; then
  [ -z "$(tail -c1 "$vault/.gitignore")" ] || echo >> "$vault/.gitignore"
  echo "$ignore" >> "$vault/.gitignore"
fi

if [ -e "$dir" ]; then echo "exists: $dir"; exit 0; fi

if [ -n "$remote" ]; then
  # A failing ls-remote (auth, network, wrong URL) stops the script via set -e.
  heads=$(git ls-remote "$remote")
  if [ -n "$heads" ]; then
    git clone -q "$remote" "$dir"
    echo "cloned: $dir"
    exit 0
  fi
fi

mkdir -p "$dir"
cp -R "$here/template"/. "$dir"/
git -C "$dir" init -q -b main
[ -z "$remote" ] || git -C "$dir" remote add origin "$remote"
git -C "$dir" add -A
git -C "$dir" commit -q -m "Start the wiki from the template"
echo "created: $dir"
