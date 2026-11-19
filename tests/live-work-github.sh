#!/usr/bin/env bash
# /work on a GitHub board, through claude -p with the stand-in gh: picks the unblocked urgent ticket,
# claims it (Status In Progress), cuts the branch from its labels, writes ticket.md with the body
# and every comment, writes the handoff, prints the route; a ticket id gets its own worktree.
. "$(dirname "$0")/lib.sh"
fixture_new; fixture_gh
export CLAUDE_MODEL=${CLAUDE_MODEL:-sonnet}
export ALLOWED_TOOLS="Skill,Read,Glob,Grep,Edit,Write,Bash(git *),Bash(bash *),Bash(VAULT=*),Bash(mkdir *),Bash(ls *)"
export CLAUDE_BUDGET=${CLAUDE_BUDGET:-2}

# setup <project dir>: fixture CLAUDE.md that stops after the route, skill installed as t-work
setup() {
  fixture_claude_md "$1"
  echo 'This is a test run: stop right after /t-work prints its `Route:` line, without starting the route.' >> "$1/CLAUDE.md"
  install_skill "$REPO_DIR/skills/work" work "$1"
}
# run_ticket <dir> <prompt>: CLAUDE_OUT = every text the assistant printed, not only the last one
run_ticket() {
  run_claude "$1" "$2" --output-format stream-json --verbose
  CLAUDE_OUT=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' <<<"$CLAUDE_OUT")
}
bq() { printf 'api graphql -F owner=QuinnNei -F name=acme-wiki -F number=%s' "$1"; }
blk() { printf '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[%s]}}}}}' "$1"; }
issue() { printf '{"number":%s,"title":"%s","body":"%s","state":"OPEN","labels":[%s],"comments":[%s]}' "$1" "$2" "$3" "$4" "$5"; }

fixture_wiki acme 'board: github' 'project: 4' 'repo: QuinnNei/acme-wiki' 'owner: QuinnNei'
acme="$PROJECTS_ROOT/acme/acme"
git -C "$acme" checkout -q -b develop
git -C "$acme" -c user.name=t -c user.email=t@acme.test commit -q --allow-empty -m "develop work"
git -C "$acme" checkout -q main

gh_can 'project item-list 4 --owner QuinnNei -L 200 --format json' '{"items":[
 {"id":"I1","status":"Todo","labels":[],"content":{"type":"Issue","number":1,"title":"Add export button","repository":"QuinnNei/acme-wiki"}},
 {"id":"I2","status":"Todo","labels":["bug","urgent"],"content":{"type":"Issue","number":2,"title":"Login fails on Safari","repository":"QuinnNei/acme-wiki"}},
 {"id":"I3","status":"Todo","labels":["urgent"],"content":{"type":"Issue","number":3,"title":"Export as PDF","repository":"QuinnNei/acme-wiki"}},
 {"id":"I4","status":"In Progress","labels":[],"content":{"type":"Issue","number":4,"title":"Older work","repository":"QuinnNei/acme-wiki"}}]}'
gh_can "$(bq 1)" "$(blk '')"
gh_can "$(bq 2)" "$(blk '')"
gh_can "$(bq 3)" "$(blk '{"number":1,"state":"OPEN","repository":{"nameWithOwner":"QuinnNei/acme-wiki"}}')"
gh_can 'issue view 2 --repo QuinnNei/acme-wiki --json number,title,body,labels,comments,state' \
  "$(issue 2 'Login fails on Safari' 'The login button does nothing on Safari 18.' '{"name":"bug"},{"name":"urgent"}' '{"author":{"login":"maria"},"body":"Reproduced on Safari 18.2 only."}')"
gh_can 'issue view 1 --repo QuinnNei/acme-wiki --json number,title,body,labels,comments,state' \
  "$(issue 1 'Add export button' 'Export the list as CSV.' '' '')"
gh_can 'project view 4 --owner QuinnNei --format json' '{"id":"PVT_1"}'
gh_can 'project field-list 4 --owner QuinnNei -L 200 --format json' '{"fields":[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]}]}'

# --- run from a linked worktree, no argument ---
wt="$FIX/acme-wt"
git -C "$acme" worktree add -q -b wt "$wt" main
setup "$wt"
run_ticket "$wt" "/t-work"

# the first ranked line, not the first number anywhere ("#3 is blocked by #1" may come before the list)
[ "$(grep -E '^[[:space:]]*([0-9]+[.)]|[-*]) .*#[123]' <<<"$CLAUDE_OUT" | grep -oE '#[123]' | head -1)" = '#2' ] && grep -q '#1' <<<"$CLAUDE_OUT" \
  && pass "pick: list printed, urgent unblocked ticket first" || { fail "pick: list printed, urgent unblocked ticket first"; echo "$CLAUDE_OUT"; }
grep -qE '^Route: /' <<<"$CLAUDE_OUT" && pass "route line printed" || { fail "route line printed"; echo "$CLAUDE_OUT" | tail -20; }
expect "claim: Status In Progress on ticket 2" "$(gh_calls)" "project item-edit --id I2 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
grep -q 'item-edit --id I[13] ' <<<"$(gh_calls)" && fail "claim: only ticket 2 changed" || pass "claim: only ticket 2 changed"
git -C "$acme" merge-base --is-ancestor develop bugfix/2 2>/dev/null \
  && pass "branch: bugfix/2 from develop" || fail "branch: bugfix/2 from develop"
t=$(ls "$acme"/.scratch/2-*/ticket.md 2>/dev/null | head -1)
[ -n "$t" ] && pass "ticket.md in the main checkout, folder 2-<slug>" || fail "ticket.md in the main checkout, folder 2-<slug>"
expect "ticket.md: branch" "$(cat "$t" 2>/dev/null)" "branch: bugfix/2"
expect "ticket.md: ref" "$(cat "$t" 2>/dev/null)" "ref: QuinnNei/acme-wiki#2"
grep -q 'The login button does nothing on Safari 18' "$t" 2>/dev/null && pass "ticket.md: body" || fail "ticket.md: body"
grep -q 'Reproduced on Safari 18.2 only' "$t" 2>/dev/null && grep -q 'maria' "$t" && pass "ticket.md: comment with author" || fail "ticket.md: comment with author"
[ ! -e "$wt/.scratch" ] && pass "nothing in the worktree's .scratch" || fail "nothing in the worktree's .scratch"
grep -qF "$t" "$acme/.handoffs/HANDOFF-2.md" 2>/dev/null \
  && pass "handoff HANDOFF-2.md points at ticket.md by absolute path" || fail "handoff HANDOFF-2.md points at ticket.md by absolute path"

# --- run from the main checkout with an id: the ticket gets its own worktree ---
git -C "$acme" checkout -q main
setup "$acme"
ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(cd *)" run_ticket "$acme" "/t-work 1"
expect "main checkout stays on main" "$(git -C "$acme" branch --show-current)" "main"
expect "ticket worktree 1 on feature/1" "$(git -C "$acme/.claude/worktrees/1" branch --show-current 2>/dev/null)" "feature/1"
[ -n "$(ls "$acme"/.scratch/1-*/ticket.md 2>/dev/null)" ] && [ ! -e "$acme/.claude/worktrees/1/.scratch" ] && pass "worktree run: ticket.md in the main checkout" \
  || { fail "worktree run: ticket.md in the main checkout"; find "$acme" -name ticket.md; echo "$CLAUDE_OUT" | tail -15; }
expect "worktree run: ticket 1 claimed" "$(gh_calls)" "project item-edit --id I1 --project-id PVT_1 --field-id F1 --single-select-option-id O2"
done_testing
