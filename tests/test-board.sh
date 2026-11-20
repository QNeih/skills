#!/usr/bin/env bash
# Board script (board.sh) with the stand-in gh: create makes the Project, its link to the code repo,
# the labels and the settings file without doing anything twice, and commits nothing; set edits one
# settings line.
. "$(dirname "$0")/lib.sh"
SK="$REPO_DIR/skills/work"
fixture_new
fixture_gh
count() { gh_calls | grep -c -- "$1" || true; }
reset_gh() { rm -f "$GH_DIR"/*; : > "$GH_LOG"; }
projects() { printf '{"projects":[%s]}' "$1"; }
linked() { printf '{"data":{"repository":{"projectsV2":{"nodes":[%s]}}}}' "$1"; }
settings() { cat "$1/.claude/project.md"; }
lacks() { grep -q "^$2:" "$1/.claude/project.md" && fail "$3" || pass "$3"; }

# Fresh project with a key, nested layout: nothing exists on GitHub yet
P="$PROJECTS_ROOT/acme/acme"
fixture_repo "$P" https://github.com/QuinnNei/acme.git
gh_can 'project create --owner QuinnNei' '7'
out=$(bash "$SK/board.sh" create "$P" --key ACM)
calls=$(gh_calls)
expect "create: Project titled <name> (<KEY>) under the repo's owner" "$calls" "project create --owner QuinnNei --title acme (ACM) --format json --jq .number"
expect "create: lists up to 200 Projects to find it by title" "$calls" "project list --owner QuinnNei -L 200 --format json"
expect "create: links the Project to the code repo" "$calls" "project link 7 --owner QuinnNei --repo QuinnNei/acme"
for l in urgent bug hotfix; do
  expect "create: label $l in the code repo" "$calls" "label create $l --repo QuinnNei/acme --force"
done
for c in 'repo create' 'repo clone'; do
  [ "$(count "^$c")" = 0 ] && pass "create: no '$c'" || fail "create: no '$c'"
done
expect "create: prints the settings file" "$out" "settings: $P/.claude/project.md"
expect "create: prints the code repo" "$out" "repo: QuinnNei/acme"
expect "create: prints the Project number" "$out" "number: 7"
expect "create: prints the owner" "$out" "owner: QuinnNei"
expect "create: prints the key" "$out" "key: ACM"
pm=$(settings "$P")
expect "create: settings are front matter" "$(head -1 <<<"$pm")" "---"
expect "create: settings board" "$pm" "board: github"
expect "create: settings Project number" "$pm" "project: 7"
expect "create: settings key" "$pm" "key: ACM"
lacks "$P" owner "create: no owner line when the Project's owner is the repo's"
[ ! -e "$PROJECTS_ROOT/acme/wiki" ] && pass "create: no wiki folder" || fail "create: no wiki folder"
expect "create: commits nothing" "$(git -C "$P" rev-list --count HEAD)" "1"
expect "create: leaves the settings file to commit" "$(git -C "$P" status --porcelain)" "?? .claude/"

# Rerun: the settings name the Project and the repo lists it; nothing is made twice
reset_gh
gh_can 'api graphql -F owner=QuinnNei -F name=acme' "$(linked '{"number":7,"owner":{"login":"QuinnNei"}}')"
before=$(settings "$P")
bash "$SK/board.sh" create "$P" >/dev/null
for c in 'project create' 'project link' 'project list' 'project edit'; do
  [ "$(count "^$c")" = 0 ] && pass "rerun: no '$c'" || fail "rerun: no '$c'"
done
[ "$(settings "$P")" = "$before" ] && pass "rerun: settings file identical" || fail "rerun: settings file identical"

# Linked to another owner's Project of the same number: still linked to this one
reset_gh
gh_can 'api graphql -F owner=QuinnNei -F name=acme' "$(linked '{"number":7,"owner":{"login":"lisegmbh"}}')"
bash "$SK/board.sh" create "$P" >/dev/null
expect "other owner's Project of that number: links this one" "$(gh_calls)" "project link 7 --owner QuinnNei --repo QuinnNei/acme"

# Flat layout, no key: the Project is titled with the name alone
F="$PROJECTS_ROOT/solo"
fixture_repo "$F" git@github.com:QNeih/solo.git
reset_gh
gh_can 'project create --owner QNeih' '3'
out=$(bash "$SK/board.sh" create "$F")
expect "flat, no key: Project titled <name>" "$(gh_calls)" "project create --owner QNeih --title solo --format json --jq .number"
expect "flat: links the code repo" "$(gh_calls)" "project link 3 --owner QNeih --repo QNeih/solo"
expect "flat: settings in the checkout" "$(settings "$F")" "project: 3"
lacks "$F" key "no key: no key line"
grep -q '^key:' <<<"$out" && fail "no key: no key printed" || pass "no key: no key printed"

# No settings yet, a Project titled <name> (<KEY>) exists: reused, its key taken over
P2="$PROJECTS_ROOT/beta/beta"
fixture_repo "$P2" https://github.com/QuinnNei/beta.git
reset_gh
gh_can 'project list --owner QuinnNei' "$(projects '{"number":9,"title":"beta-old (BO)"},{"number":4,"title":"beta (BET)"},{"number":5,"title":"other"}')"
out=$(bash "$SK/board.sh" create "$P2")
expect "found by title with a key: reused" "$out" "number: 4"
expect "found by title with a key: key taken from the title" "$(settings "$P2")" "key: BET"
expect "found by title: linked" "$(gh_calls)" "project link 4 --owner QuinnNei --repo QuinnNei/beta"
for c in 'project create' 'project edit'; do
  [ "$(count "^$c")" = 0 ] && pass "found by title: no '$c'" || fail "found by title: no '$c'"
done

# A Project titled <name> alone and a key given: reused, and its title gets the key
P3="$PROJECTS_ROOT/gamma/gamma"
fixture_repo "$P3" https://github.com/QuinnNei/gamma.git
reset_gh
gh_can 'project list --owner QuinnNei' "$(projects '{"number":6,"title":"gamma"}')"
out=$(bash "$SK/board.sh" create "$P3" --key GAM)
expect "found by title without a key: reused" "$out" "number: 6"
expect "found by title without a key: title gets the key" "$(gh_calls)" "project edit 6 --owner QuinnNei --title gamma (GAM)"
[ "$(count '^project create')" = 0 ] && pass "found by title without a key: none created" || fail "found by title without a key: none created"

# A Project of that name under another key is another board: a new one is made
P4="$PROJECTS_ROOT/delta/delta"
fixture_repo "$P4" https://github.com/QuinnNei/delta.git
reset_gh
gh_can 'project list --owner QuinnNei' "$(projects '{"number":8,"title":"delta (OLD)"}')"
gh_can 'project create --owner QuinnNei' '12'
out=$(bash "$SK/board.sh" create "$P4" --key DLT)
expect "another key in the title: new Project" "$(gh_calls)" "project create --owner QuinnNei --title delta (DLT) --format json --jq .number"
expect "another key in the title: its number" "$out" "number: 12"

# The Project under another owner than the repo's: owner saved; from a ticket worktree the settings land in the main checkout
P5="$PROJECTS_ROOT/eps/eps"
fixture_repo "$P5" https://github.com/QuinnNei/eps.git
fixture_worktree "$P5" 2
reset_gh
gh_can 'project create --owner lisegmbh' '10'
out=$(bash "$SK/board.sh" create "$P5/.claude/worktrees/2" --owner lisegmbh)
expect "other owner: Project under it" "$(gh_calls)" "project create --owner lisegmbh --title eps --format json --jq .number"
expect "other owner: linked to the code repo" "$(gh_calls)" "project link 10 --owner lisegmbh --repo QuinnNei/eps"
expect "other owner: saved" "$(settings "$P5")" "owner: lisegmbh"
expect "from a worktree: settings in the main checkout" "$out" "settings: $P5/.claude/project.md"
[ ! -e "$P5/.claude/worktrees/2/.claude/project.md" ] && pass "from a worktree: none in the worktree" || fail "from a worktree: none in the worktree"
# and the saved owner and key are used on the next run
reset_gh
bash "$SK/board.sh" set "$P5" key EPS >/dev/null
sed -i.bak '/^project:/d' "$P5/.claude/project.md" && rm "$P5/.claude/project.md.bak"
gh_can 'project list --owner lisegmbh' "$(projects '{"number":10,"title":"eps (EPS)"}')"
out=$(bash "$SK/board.sh" create "$P5")
expect "settings owner and key: found again by title" "$out" "number: 10"
expect "settings owner: asked for its Projects" "$(gh_calls | head -1)" "project list --owner lisegmbh -L 200 --format json"

# A repo setting names the code repo when the checkout has no origin; with neither it fails before any gh call
P6="$PROJECTS_ROOT/zeta/zeta"
fixture_repo "$P6"
reset_gh
err=$(bash "$SK/board.sh" create "$P6" 2>&1 >/dev/null) && fail "no origin: fails" || pass "no origin: fails"
expect "no origin: says why" "$err" "board.sh: $P6 has no origin: the board needs the code repo on GitHub"
expect "no origin: nothing asked of GitHub" "$([ -z "$(gh_calls)" ] && echo none)" "none"
bash "$SK/board.sh" set "$P6" repo Org/zeta-code >/dev/null
gh_can 'project create --owner Org' '2'
bash "$SK/board.sh" create "$P6" >/dev/null
expect "repo setting: Project linked to it" "$(gh_calls)" "project link 2 --owner Org --repo Org/zeta-code"
expect "repo setting: labels go to it" "$(gh_calls)" "label create urgent --repo Org/zeta-code --force"

# set: exactly one settings line changes
printf -- '---\nboard: github\nproject: 7\nsentry: acme-web\nclose: merge\n---\nbody stays\n' > "$P/.claude/project.md"
before=$(settings "$P")
out=$(bash "$SK/board.sh" set "$P" close pr)
after=$(settings "$P")
expect "set: prints the file" "$out" "saved: close in $P/.claude/project.md"
expect "set: line replaced" "$after" "close: pr"
[ "$(diff <(echo "$before") <(echo "$after") | grep -c '^[<>]')" = 2 ] && pass "set: exactly one line differs" || fail "set: exactly one line differs"
bash "$SK/board.sh" set "$P" key SKL >/dev/null
expect "set: missing line added" "$(settings "$P")" "key: SKL"
expect "set: body kept" "$(settings "$P")" "body stays"
[ "$(grep -c '^key:' "$P/.claude/project.md")" = 1 ] && pass "set: one key line" || fail "set: one key line"
# set creates the settings file: a board that is a link needs no GitHub Project
P7="$PROJECTS_ROOT/eta"
fixture_repo "$P7"
reset_gh
bash "$SK/board.sh" set "$P7" board "https://boards.acme.test/org/eta" >/dev/null
expect "set: creates the settings file" "$(settings "$P7")" "board: https://boards.acme.test/org/eta"
expect "set: front matter" "$(head -1 "$P7/.claude/project.md")" "---"
expect "set: no gh call" "$([ -z "$(gh_calls)" ] && echo none)" "none"
done_testing
