#!/usr/bin/env bash
# Project lookup (skills/work/project.sh): layout, worktree, settings (wiki or code repo), Jira, no wiki.
. "$(dirname "$0")/lib.sh"
LOOKUP="$REPO_DIR/skills/work/project.sh"
fixture_new
lookup() { (cd "$1" && "$LOOKUP" "${@:2}" 2>&1); }
absent() { grep -q "^$2:" <<<"$1" && fail "no $2 line" || pass "no $2 line"; }

# Layout: wiki next to the repo, settings from project.md, everything printed
fixture_wiki acme "board: github" "project: 7" "owner: QuinnNei" "repo: QuinnNei/acme-wiki"
out=$(lookup "$PROJECTS_ROOT/acme/acme"); rc=$?
expect "layout: dir" "$out" "dir: $PROJECTS_ROOT/acme/acme"
expect "layout: project is the parent folder's name" "$out" "project: acme"
expect "layout: wiki" "$out" "wiki: $PROJECTS_ROOT/acme/wiki"
expect "layout: board" "$out" "board: github"
expect "layout: repo" "$out" "repo: QuinnNei/acme-wiki"
expect "layout: number" "$out" "number: 7"
expect "layout: owner" "$out" "owner: QuinnNei"
absent "$out" key
[ $rc -eq 0 ] && pass "exits 0" || fail "exits 0 (got $rc)"

# Subfolder of the main checkout
mkdir -p "$PROJECTS_ROOT/acme/acme/src/deep"
out=$(lookup "$PROJECTS_ROOT/acme/acme/src/deep")
expect "subfolder: dir is the main checkout" "$out" "dir: $PROJECTS_ROOT/acme/acme"

# Worktree inside the project repo and a worktree elsewhere resolve to the main checkout
fixture_wiki_worktree acme SKL-1
out=$(lookup "$PROJECTS_ROOT/acme/acme/.claude/worktrees/SKL-1")
expect "worktree: dir" "$out" "dir: $PROJECTS_ROOT/acme/acme"
expect "worktree: project" "$out" "project: acme"
expect "worktree: wiki" "$out" "wiki: $PROJECTS_ROOT/acme/wiki"
git -C "$PROJECTS_ROOT/acme/acme" worktree add -q "$FIX/wt-acme" -b other
expect "worktree elsewhere: dir" "$(lookup "$FIX/wt-acme")" "dir: $PROJECTS_ROOT/acme/acme"

# Defaults: no settings → github; repo and owner from the wiki's origin
fixture_wiki beta
git -C "$PROJECTS_ROOT/beta/wiki" remote add origin git@github.com:Org/beta-wiki.git
out=$(lookup "$PROJECTS_ROOT/beta/beta")
expect "default board" "$out" "board: github"
expect "repo from the wiki origin (scp-like)" "$out" "repo: Org/beta-wiki"
expect "owner from the wiki origin" "$out" "owner: Org"
absent "$out" number

# https origin with .git
fixture_wiki gamma
git -C "$PROJECTS_ROOT/gamma/wiki" remote add origin https://github.com/Org2/gamma-wiki.git
expect "repo from an https origin" "$(lookup "$PROJECTS_ROOT/gamma/gamma")" "repo: Org2/gamma-wiki"

# No wiki remote: owner from the project repo's origin, no repo line
fixture_wiki delta "project: 3"
git -C "$PROJECTS_ROOT/delta/delta" remote add origin https://github.com/Own/delta.git
out=$(lookup "$PROJECTS_ROOT/delta/delta")
expect "owner from the project repo" "$out" "owner: Own"
absent "$out" repo

# Jira: board and key from the settings
fixture_wiki construct "board: jira" "key: CON"
out=$(lookup "$PROJECTS_ROOT/construct/construct")
expect "jira: board" "$out" "board: jira"
expect "jira: key" "$out" "key: CON"

# Another tracker: the board value is printed as written
fixture_wiki trello "board: https://boards.acme.test/org/trello"
expect "other board" "$(lookup "$PROJECTS_ROOT/trello/trello")" "board: https://boards.acme.test/org/trello"

# No wiki: project none, a reason that names the board step
fixture_repo "$PROJECTS_ROOT/lone/lone"
out=$(lookup "$PROJECTS_ROOT/lone/lone"); rc=$?
expect "no wiki: no project" "$out" "project: none"
expect "no wiki: reason names both places" "$out" "reason: no wiki at $PROJECTS_ROOT/lone/wiki and no settings at $PROJECTS_ROOT/lone/lone/.claude/project.md: run the board step to create the wiki and the board"
[ $rc -eq 0 ] && pass "no wiki exits 0" || fail "no wiki exits 0 (got $rc)"

# No wiki folder, settings in the code repo's .claude/project.md
fixture_repo "$PROJECTS_ROOT/solo/solo" https://github.com/QNeih/solo.git
mkdir -p "$PROJECTS_ROOT/solo/solo/.claude"
printf '%s\n' --- "project: 3" --- > "$PROJECTS_ROOT/solo/solo/.claude/project.md"
out=$(lookup "$PROJECTS_ROOT/solo/solo"); rc=$?
expect "code settings: project" "$out" "project: solo"
expect "code settings: board defaults to github" "$out" "board: github"
expect "code settings: repo defaults to the code repo's origin" "$out" "repo: QNeih/solo"
expect "code settings: owner defaults to the origin's owner" "$out" "owner: QNeih"
expect "code settings: number" "$out" "number: 3"
absent "$out" wiki
[ $rc -eq 0 ] && pass "code settings exit 0" || fail "code settings exit 0 (got $rc)"
printf '%s\n' --- "project: 4" "owner: Other" "repo: Other/tickets" "key: SO" --- > "$PROJECTS_ROOT/solo/solo/.claude/project.md"
fixture_wiki_worktree solo T-1
out=$(lookup "$PROJECTS_ROOT/solo/solo/.claude/worktrees/T-1")
expect "code settings: worktree reads the main checkout" "$out" "dir: $PROJECTS_ROOT/solo/solo"
expect "code settings: repo override" "$out" "repo: Other/tickets"
expect "code settings: owner override" "$out" "owner: Other"
expect "code settings: key" "$out" "key: SO"
# A wiki folder wins over .claude/project.md
fixture_wiki both "board: jira"
mkdir -p "$PROJECTS_ROOT/both/both/.claude"; printf '%s\n' --- "board: github" --- > "$PROJECTS_ROOT/both/both/.claude/project.md"
out=$(lookup "$PROJECTS_ROOT/both/both")
expect "wiki wins: board" "$out" "board: jira"
expect "wiki wins: wiki line" "$out" "wiki: $PROJECTS_ROOT/both/wiki"

# Not a git folder, no wiki
mkdir -p "$FIX/plain/x"
expect "no git, no wiki" "$(lookup "$FIX/plain/x")" "project: none"

# The vault plays no part: no VAULT needed, a vault note is ignored
expect "no VAULT needed" "$(cd "$PROJECTS_ROOT/acme/acme" && env -u VAULT "$LOOKUP" | sed -n 2p)" "project: acme"

# Reverse lookup by name, ignoring case, spaces and hyphens
fixture_wiki "Acme Proto" "project: 9"
out=$(lookup "$FIX" --name acme-proto)
expect "reverse: dir" "$out" "dir: $PROJECTS_ROOT/Acme Proto/Acme Proto"
expect "reverse: number" "$out" "number: 9"
expect "reverse: --note alias" "$(lookup "$FIX" --note acme)" "project: acme"
expect "reverse: no folder" "$(lookup "$FIX" --name Nope)" "reason: no project folder named Nope under the projects root"

done_testing
