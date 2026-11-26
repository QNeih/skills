#!/usr/bin/env bash
# Project lookup (skills/work/project.sh): nested and flat layout, worktree, settings file, no settings file, key, origin host and PR, Jira, lookup by name.
. "$(dirname "$0")/lib.sh"
LOOKUP="$REPO_DIR/skills/work/project.sh"
fixture_new
lookup() { (cd "$1" && "$LOOKUP" "${@:2}" 2>&1); }
absent() { grep -q "^$2:" <<<"$1" && fail "$3: no $2 line" || pass "$3: no $2 line"; }

# Nested layout: the checkout in a project folder of its own name, every setting printed
fixture_project acme "board: github" "project: 7" "owner: QuinnNei" "repo: QuinnNei/acme" "key: ACM"
out=$(lookup "$PROJECTS_ROOT/acme/acme"); rc=$?
expect "nested: dir is the checkout" "$out" "dir: $PROJECTS_ROOT/acme/acme"
expect "nested: project is the folder's name" "$out" "project: acme"
expect "nested: board" "$out" "board: github"
expect "nested: repo" "$out" "repo: QuinnNei/acme"
expect "nested: number" "$out" "number: 7"
expect "nested: owner" "$out" "owner: QuinnNei"
expect "nested: key" "$out" "key: ACM"
absent "$out" wiki "nested without a wiki folder"
absent "$out" reason "nested with settings"
[ $rc -eq 0 ] && pass "exits 0" || fail "exits 0 (got $rc)"

# A sibling wiki folder is named, and its files are not read
mkdir -p "$PROJECTS_ROOT/acme/wiki"
printf '%s\n' --- "board: jira" "project: 99" --- > "$PROJECTS_ROOT/acme/wiki/project.md"
out=$(lookup "$PROJECTS_ROOT/acme/acme")
expect "nested: sibling wiki folder" "$out" "wiki: $PROJECTS_ROOT/acme/wiki"
expect "a project.md in the wiki folder is not read: board" "$out" "board: github"
expect "a project.md in the wiki folder is not read: number" "$out" "number: 7"

# Subfolder of the main checkout
mkdir -p "$PROJECTS_ROOT/acme/acme/src/deep"
expect "subfolder: dir is the main checkout" "$(lookup "$PROJECTS_ROOT/acme/acme/src/deep")" "dir: $PROJECTS_ROOT/acme/acme"

# A ticket worktree and a worktree elsewhere resolve to the main checkout and its settings file
fixture_worktree "$PROJECTS_ROOT/acme/acme" ACM-1
printf '%s\n' --- "project: 1" --- > "$PROJECTS_ROOT/acme/acme/.claude/worktrees/ACM-1/.claude/project.md"
out=$(lookup "$PROJECTS_ROOT/acme/acme/.claude/worktrees/ACM-1")
expect "worktree: dir" "$out" "dir: $PROJECTS_ROOT/acme/acme"
expect "worktree: project" "$out" "project: acme"
expect "worktree: settings of the main checkout, not the worktree's copy" "$out" "number: 7"
expect "worktree: wiki" "$out" "wiki: $PROJECTS_ROOT/acme/wiki"
git -C "$PROJECTS_ROOT/acme/acme" worktree add -q "$FIX/wt-acme" -b other
expect "worktree elsewhere: dir" "$(lookup "$FIX/wt-acme")" "dir: $PROJECTS_ROOT/acme/acme"

# Flat layout: the folder under the projects root is the checkout
fixture_project_flat solo "project: 3"
git -C "$PROJECTS_ROOT/solo" remote add origin https://github.com/QNeih/solo.git
out=$(lookup "$PROJECTS_ROOT/solo")
expect "flat: dir is the folder" "$out" "dir: $PROJECTS_ROOT/solo"
expect "flat: project is the folder's name" "$out" "project: solo"
expect "flat: board defaults to github" "$out" "board: github"
expect "flat: repo defaults to the origin (https)" "$out" "repo: QNeih/solo"
expect "flat: owner defaults to the repo's owner" "$out" "owner: QNeih"
expect "flat: number" "$out" "number: 3"
expect "https origin on github.com: host" "$out" "host: github.com"
expect "https origin on github.com: PR" "$out" "pr: yes"
absent "$out" key "no key setting"
# A wiki folder next to a flat checkout is another project's folder
mkdir -p "$PROJECTS_ROOT/wiki"
absent "$(lookup "$PROJECTS_ROOT/solo")" wiki "flat"
fixture_worktree "$PROJECTS_ROOT/solo" 4
out=$(lookup "$PROJECTS_ROOT/solo/.claude/worktrees/4")
expect "flat worktree: dir" "$out" "dir: $PROJECTS_ROOT/solo"
expect "flat worktree: project" "$out" "project: solo"

# Settings override the origin: the board's repo and the Project's owner
fixture_project_flat over "project: 4" "owner: Other" "repo: Other/tickets" "key: OV"
git -C "$PROJECTS_ROOT/over" remote add origin git@github.com:Org/over.git
out=$(lookup "$PROJECTS_ROOT/over")
expect "override: repo" "$out" "repo: Other/tickets"
expect "override: owner" "$out" "owner: Other"
expect "override: key" "$out" "key: OV"

# scp-like origin; an owner setting next to the origin's repo
fixture_project beta "owner: lisegmbh"
git -C "$PROJECTS_ROOT/beta/beta" remote add origin git@github.com:Org/beta.git
out=$(lookup "$PROJECTS_ROOT/beta/beta")
expect "repo from the origin (scp-like)" "$out" "repo: Org/beta"
expect "scp-like origin on github.com: host" "$out" "host: github.com"
expect "scp-like origin on github.com: PR" "$out" "pr: yes"
expect "owner setting wins over the repo's owner" "$out" "owner: lisegmbh"
absent "$out" number "no project setting"

# No origin and no repo setting: no repo and no owner line
fixture_project delta "project: 3"
out=$(lookup "$PROJECTS_ROOT/delta/delta")
expect "no origin: number still printed" "$out" "number: 3"
absent "$out" repo "no origin"
absent "$out" owner "no origin"
absent "$out" host "no origin"
absent "$out" pr "no origin"

# Origins off github.com: the host as the lookup reads it, and no PR, even with a GitHub repo setting
fixture_project_flat local "repo: QNeih/local"
git -C "$PROJECTS_ROOT/local" remote add origin "$FIX/local.git"
out=$(lookup "$PROJECTS_ROOT/local")
expect "local path origin: the path is the host" "$out" "host: $FIX/local.git"
expect "local path origin: no PR, despite the repo setting" "$out" "pr: no"
git -C "$PROJECTS_ROOT/local" remote set-url origin file:///srv/git/local.git
expect "file URL origin: the path is the host" "$(lookup "$PROJECTS_ROOT/local")" "host: /srv/git/local.git"
git -C "$PROJECTS_ROOT/local" remote set-url origin ssh://git@gitlab.example.com:2222/team/local.git
out=$(lookup "$PROJECTS_ROOT/local")
expect "ssh URL with user and port: host" "$out" "host: gitlab.example.com"
expect "ssh URL off github.com: no PR" "$out" "pr: no"
git -C "$PROJECTS_ROOT/local" remote set-url origin https://GitHub.com/QNeih/local.git
expect "host in upper case: lower-cased, PR" "$(lookup "$PROJECTS_ROOT/local")" "pr: yes"
git -C "$PROJECTS_ROOT/local" remote set-url origin https://user@dev.azure.com/org/proj/_git/local
expect "https URL with user: host" "$(lookup "$PROJECTS_ROOT/local")" "host: dev.azure.com"

# Jira: board and key from the settings
fixture_project_flat construct "board: jira" "key: CON"
out=$(lookup "$PROJECTS_ROOT/construct")
expect "jira: board" "$out" "board: jira"
expect "jira: key" "$out" "key: CON"

# Another tracker: the board value is printed as written
fixture_project trello "board: https://boards.acme.test/org/trello"
expect "other board" "$(lookup "$PROJECTS_ROOT/trello/trello")" "board: https://boards.acme.test/org/trello"

# No settings file: the project is known, the board is not
fixture_repo "$PROJECTS_ROOT/lone/lone" https://github.com/QNeih/lone.git
mkdir -p "$PROJECTS_ROOT/lone/wiki"
out=$(lookup "$PROJECTS_ROOT/lone/lone"); rc=$?
expect "no settings, nested: dir" "$out" "dir: $PROJECTS_ROOT/lone/lone"
expect "no settings, nested: project" "$out" "project: lone"
expect "no settings, nested: wiki" "$out" "wiki: $PROJECTS_ROOT/lone/wiki"
expect "no settings, nested: board none" "$out" "board: none"
expect "no settings, nested: reason names the file and the board step" "$out" "reason: no settings file $PROJECTS_ROOT/lone/lone/.claude/project.md: the board step has not run"
for k in repo number owner key; do absent "$out" "$k" "no settings"; done
[ $rc -eq 0 ] && pass "no settings exits 0" || fail "no settings exits 0 (got $rc)"
fixture_repo "$PROJECTS_ROOT/bare"
out=$(lookup "$PROJECTS_ROOT/bare")
expect "no settings, flat: project" "$out" "project: bare"
expect "no settings, flat: board none" "$out" "board: none"

# No git: a settings file makes the folder a project; without one there is none
mkdir -p "$PROJECTS_ROOT/docs/docs/.claude"
printf '%s\n' --- "board: github" "project: 5" "repo: QNeih/docs" --- > "$PROJECTS_ROOT/docs/docs/.claude/project.md"
out=$(lookup "$PROJECTS_ROOT/docs/docs")
expect "no git, settings: project" "$out" "project: docs"
expect "no git, settings: repo" "$out" "repo: QNeih/docs"
expect "no git, settings: owner" "$out" "owner: QNeih"
mkdir -p "$FIX/plain/x"
out=$(lookup "$FIX/plain/x"); rc=$?
expect "no git, no settings: dir" "$out" "dir: $FIX/plain/x"
expect "no git, no settings: no project" "$out" "project: none"
expect "no git, no settings: reason" "$out" "reason: $FIX/plain/x is no git checkout and has no settings file .claude/project.md"
absent "$out" board "no project"
[ $rc -eq 0 ] && pass "no project exits 0" || fail "no project exits 0 (got $rc)"

# The vault plays no part: no VAULT needed
expect "no VAULT needed" "$(cd "$PROJECTS_ROOT/acme/acme" && env -u VAULT "$LOOKUP" | sed -n 2p)" "project: acme"

# Lookup by name, ignoring case, spaces and hyphens
fixture_project "Acme Proto" "project: 9"
out=$(lookup "$FIX" --name acme-proto)
expect "by name, nested: dir is the inner checkout" "$out" "dir: $PROJECTS_ROOT/Acme Proto/Acme Proto"
expect "by name, nested: project" "$out" "project: Acme Proto"
expect "by name, nested: number" "$out" "number: 9"
out=$(lookup "$FIX" --name SOLO)
expect "by name, flat: dir is the folder" "$out" "dir: $PROJECTS_ROOT/solo"
expect "by name, flat: number" "$out" "number: 3"
expect "by name: --note alias" "$(lookup "$FIX" --note acme)" "dir: $PROJECTS_ROOT/acme/acme"
# A flat checkout that holds a folder of its own name stays flat
fixture_project_flat tool "project: 12"
mkdir -p "$PROJECTS_ROOT/tool/tool"
out=$(lookup "$FIX" --name tool)
expect "by name: a checkout with an inner folder of its name is flat" "$out" "dir: $PROJECTS_ROOT/tool"
expect "by name: its settings" "$out" "number: 12"
expect "by name, no settings: board none" "$(lookup "$FIX" --name lone)" "board: none"
expect "by name: no folder" "$(lookup "$FIX" --name Nope)" "reason: no project folder named Nope under the projects root"
expect "by name: needs the projects root" "$(cd "$FIX" && env -u PROJECTS_ROOT "$LOOKUP" --name acme)" "reason: PROJECTS_ROOT must be set"

done_testing
