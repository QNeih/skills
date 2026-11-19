#!/usr/bin/env bash
# Board script (board.sh) with the stand-in gh: create makes the wiki repo, Project, labels,
# link, clone and project.md without doing anything twice; set edits one settings line.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work"
fixture_new
fixture_gh
P="$PROJECTS_ROOT/acme"
fixture_repo "$P/acme" https://github.com/QuinnNei/acme.git
count() { gh_calls | grep -c -- "$1" || true; }
reset_gh() { rm -f "$GH_DIR"/*; : > "$GH_LOG"; }

# fresh project: nothing exists on GitHub yet
gh_can 'project create --owner QuinnNei' '7'
out=$(bash "$SK/board.sh" create "$P/acme")
calls=$(gh_calls)
expect "create: private wiki repo under the project repo's owner" "$calls" "repo create QuinnNei/acme-wiki --private"
expect "create: Project under the same owner" "$calls" "project create --owner QuinnNei --title acme --format json --jq .number"
expect "create: links the Project to the wiki" "$calls" "project link 7 --owner QuinnNei --repo QuinnNei/acme-wiki"
for l in urgent bug hotfix; do
  expect "create: label $l" "$calls" "label create $l --repo QuinnNei/acme-wiki --force"
done
expect "create: clones the wiki into the layout" "$calls" "repo clone QuinnNei/acme-wiki $P/wiki"
expect "create: prints the wiki" "$out" "wiki: $P/wiki"
expect "create: prints the Project number" "$out" "number: 7"
expect "create: prints the owner" "$out" "owner: QuinnNei"
pm=$(cat "$P/wiki/project.md")
expect "create: project.md is front matter" "$(head -1 <<<"$pm")" "---"
expect "create: project.md board" "$pm" "board: github"
expect "create: project.md Project number" "$pm" "project: 7"

# rerun: everything exists, nothing is created twice
reset_gh
gh_can 'repo view QuinnNei/acme-wiki' 'QuinnNei/acme-wiki'
gh_can 'project list --owner QuinnNei' '7'
bash "$SK/board.sh" create "$P/acme" >/dev/null
for c in 'repo create' 'project create' 'project link' 'repo clone'; do
  [ "$(count "^$c")" = 0 ] && pass "rerun: no '$c'" || fail "rerun: no '$c'"
done
[ "$(grep -c '^project:' "$P/wiki/project.md")" = 1 ] && pass "rerun: one project line" || fail "rerun: one project line"

# half-made: wiki repo exists but no local Project record; the Project of that title is reused
P2="$PROJECTS_ROOT/beta"
fixture_repo "$P2/beta" git@github.com:QuinnNei/beta.git
reset_gh
gh_can 'repo view QuinnNei/beta-wiki' 'QuinnNei/beta-wiki'
gh_can 'project list --owner QuinnNei' '4'
out=$(bash "$SK/board.sh" create "$P2/beta")
expect "half-made: keeps the wiki repo" "$([ "$(count '^repo create')" = 0 ] && echo kept)" "kept"
expect "half-made: reuses the Project" "$out" "number: 4"
expect "half-made: links it" "$(gh_calls)" "project link 4 --owner QuinnNei --repo QuinnNei/beta-wiki"

# project without a remote: the owner is given; without one it fails
P3="$PROJECTS_ROOT/gamma"
fixture_repo "$P3/gamma"
reset_gh
gh_can 'project create --owner' '9'
if bash "$SK/board.sh" create "$P3/gamma" >/dev/null 2>&1; then fail "no owner: fails"; else pass "no owner: fails"; fi
expect "no owner: nothing asked of GitHub" "$([ -z "$(gh_calls)" ] && echo none)" "none"
bash "$SK/board.sh" create "$P3/gamma" --owner lisegmbh >/dev/null
expect "owner given: wiki repo under it" "$(gh_calls)" "repo create lisegmbh/gamma-wiki --private"

# set: exactly one settings line changes
W="$P/wiki"
printf -- '---\nboard: github\nproject: 7\nsentry: acme-web\nclose: merge\n---\nbody stays\n' > "$W/project.md"
before=$(cat "$W/project.md")
bash "$SK/board.sh" set "$W" close pr >/dev/null
after=$(cat "$W/project.md")
expect "set: line replaced" "$after" "close: pr"
[ "$(diff <(echo "$before") <(echo "$after") | grep -c '^[<>]')" = 2 ] && pass "set: exactly one line differs" || fail "set: exactly one line differs"
bash "$SK/board.sh" set "$W" key SKL >/dev/null
expect "set: missing line added" "$(cat "$W/project.md")" "key: SKL"
expect "set: body kept" "$(cat "$W/project.md")" "body stays"
[ "$(grep -c '^key:' "$W/project.md")" = 1 ] && pass "set: one key line" || fail "set: one key line"
done_testing
