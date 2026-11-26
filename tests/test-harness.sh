#!/usr/bin/env bash
# The claude -p harness parts that run without claude: skill install, fixture CLAUDE.md, sandbox and guard, claude lookup.
. "$(dirname "$0")/lib.sh"
fixture_new

src=$(mktemp -d /tmp/skills-test-src.XXXXXX); trap 'rm -rf "$FIX" "$src"' EXIT
printf -- '---\nname: probe\ndescription: test\n---\nBody name: probe\n' > "$src/SKILL.md"
echo helper > "$src/helper.sh"
fixture_repo "$PROJECTS_ROOT/acme"
fixture_claude_md "$PROJECTS_ROOT/acme"
install_skill "$src" probe "$PROJECTS_ROOT/acme"
t="$PROJECTS_ROOT/acme/.claude/skills/t-probe"
expect "install: name rewritten" "$(cat "$t/SKILL.md")" "name: t-probe"
expect "install: body kept" "$(cat "$t/SKILL.md")" "Body name: probe"
[ -f "$t/helper.sh" ] && pass "install: skill files copied" || fail "install: skill files copied"
grep -qF "$VAULT" "$PROJECTS_ROOT/acme/CLAUDE.md" && grep -qF "$PROJECTS_ROOT" "$PROJECTS_ROOT/acme/CLAUDE.md" \
  && pass "fixture CLAUDE.md names fixture paths" || fail "fixture CLAUDE.md names fixture paths"

# Guard: stand-in real dirs, so nothing real is touched
fake=$(cd "$src" && pwd -P)
mkdir -p "$fake/vault/audit" "$fake/home/.claude/skills/synced" "$fake/home/.claude/skills/send" "$fake/projects/other/.scratch" \
  "$fake/projects/other/other/.claude/worktrees/OT-1/.handoffs" "$fake/projects/flat/src"
export REAL_VAULT="$fake/vault" REAL_HOME="$fake/home" REAL_PROJECTS_ROOT="$fake/projects"
# record <tool output>: a run's record whose one tool result holds the output
record() { jq -cn --arg o "$1" '{type: "user", message: {content: [{type: "tool_result", content: $o}]}}' > "$FIX/record.jsonl"; }

guard_start
# another session writes to the real locations while the sandboxed run writes to the fixture
touch "$fake/vault/audit/note.md" "$fake/projects/other/.scratch/x.md" "$fake/projects/other/other/.claude/worktrees/OT-1/.handoffs/HANDOFF-OT-1.md"
record "$(guard_exec bash -c 'echo hi > "$1/fixture-file" && echo hi > "$2/cache"' _ "$FIX" "$fake/home/.claude/skills/synced" 2>&1)"
[ -f "$FIX/fixture-file" ] && pass "sandbox: the fixture stays writable" || fail "sandbox: the fixture stays writable: $(cat "$FIX/record.jsonl")"
[ -f "$fake/home/.claude/skills/synced/cache" ] && pass "sandbox: the skill-sync cache stays writable" || fail "sandbox: the skill-sync cache stays writable"
out=$(guard_check "$FIX/record.jsonl") && pass "guard: another session's writes to real locations pass" \
  || fail "guard: another session's writes to real locations pass: $out"

# the run itself writes to each denied location, the last one from a child process
denied=("$fake/vault/own note.md" "$fake/home/.claude/skills/send/SKILL.md" "$fake/projects/other/.scratch/own.md" "$fake/projects/flat/src/main.c")
record "$(guard_exec bash -c 'for f; do echo hi > "$f"; done; touch "$0"' "$fake/vault/child.md" "${denied[@]}" 2>&1)"
denied+=("$fake/vault/child.md")
ok=1; for f in "${denied[@]}"; do [ ! -e "$f" ] || ok=0; done
[ $ok -eq 1 ] && pass "sandbox: writes to real locations are blocked" || fail "sandbox: writes to real locations are blocked"
out=$(guard_check "$FIX/record.jsonl") && fail "guard: the run's own write fails it" || pass "guard: the run's own write fails it"
ok=1; for f in "${denied[@]}"; do grep -qxF "$f" <<<"$out" || ok=0; done
[ $ok -eq 1 ] && pass "guard: names each blocked file" || fail "guard: names each blocked file: $out"

# an Edit or Write tool's error: lower case, the tool result's content a list of text parts
jq -cn --arg o "EPERM: operation not permitted, open '$fake/vault/tool.md'" \
  '{type: "user", message: {content: [{type: "tool_result", is_error: true, content: [{type: "text", text: $o}]}]}}' > "$FIX/record.jsonl"
expect "guard: names a file tool's blocked write" "$(guard_check "$FIX/record.jsonl")" "$fake/vault/tool.md"
# a refusal outside the denied locations is not the guard's business
record "rm: /etc/hosts: Operation not permitted"
out=$(guard_check "$FIX/record.jsonl") && pass "guard: a refusal outside the real locations passes" || fail "guard: a refusal outside the real locations passes: $out"
# a tool that puts the reason behind the path
record "error: unable to open $fake/vault/own note.md for writing (Operation not permitted)
fatal: cannot create $fake/projects/flat/src/gen.c (Operation not permitted)"
out=$(guard_check "$FIX/record.jsonl")
expect "guard: names the file before 'for writing'" "$out" "$fake/vault/own note.md"
expect "guard: names the file before the bracketed reason" "$out" "$fake/projects/flat/src/gen.c"

# a record that cannot be checked must not pass
out=$(guard_check "$FIX/no-record.jsonl" 2>/dev/null) && fail "guard: a missing record fails" || pass "guard: a missing record fails"
echo "sandbox_apply: Operation not permitted" > "$FIX/record.jsonl"
out=$(guard_check "$FIX/record.jsonl") && fail "guard: a record without a JSON line fails" || pass "guard: a record without a JSON line fails"
grep -q 'holds no JSON line' <<<"$out" && pass "guard: says the record cannot be checked" || fail "guard: says the record cannot be checked: $out"

# a location reached through a symlink, and one whose name holds the profile's quoting characters
ln -s "$fake/vault" "$FIX/vault-link"
odd="$fake/pro\"j\\ects"; mkdir -p "$odd/app"
REAL_VAULT="$FIX/vault-link" REAL_PROJECTS_ROOT="$odd"
guard_start
record "$(guard_exec bash -c 'for f; do echo hi > "$f"; done' _ "$FIX/vault-link/linked.md" "$odd/app/a.md" "$FIX/beside.md" 2>&1)"
[ ! -e "$fake/vault/linked.md" ] && pass "sandbox: a write through a symlinked location is blocked" || fail "sandbox: a write through a symlinked location is blocked"
[ ! -e "$odd/app/a.md" ] && [ -f "$FIX/beside.md" ] && pass "sandbox: a location with quote and backslash is blocked, the fixture is not" \
  || fail "sandbox: a location with quote and backslash is blocked, the fixture is not: $(cat "$FIX/record.jsonl")"
out=$(guard_check "$FIX/record.jsonl")
expect "guard: names the file by its symlinked path" "$out" "$FIX/vault-link/linked.md"
expect "guard: names the file under a quoted location" "$out" "$odd/app/a.md"

REAL_HOME="$fake/missing"
out=$(guard_start 2>&1) && fail "guard: a missing real location stops the run" || pass "guard: a missing real location stops the run"
REAL_HOME="$fake/home"

# claude lookup: stand-in binaries and a stand-in HOME, on a PATH that holds no real claude
bare=/usr/bin:/bin
mkdir -p "$fake/onpath" "$fake/home/.local/bin" "$fake/nohome"
for d in "$fake/onpath" "$fake/home/.local/bin"; do
  printf '#!/bin/sh\necho "stand-in at $0 got: $*"\n' > "$d/claude"; chmod +x "$d/claude"
done
out=$(HOME="$fake/home" PATH="$fake/onpath:$bare" find_claude)
[ "$out" = "$fake/onpath/claude" ] && pass "lookup: claude on PATH wins" || fail "lookup: claude on PATH wins: $out"
out=$(HOME="$fake/home" PATH="$bare" find_claude)
[ "$out" = "$fake/home/.local/bin/claude" ] && pass "lookup: falls back to ~/.local/bin" || fail "lookup: falls back to ~/.local/bin: $out"
out=$(export HOME="$fake/home" PATH="$bare"; run_claude "$PROJECTS_ROOT/acme" "say hi"; echo "$CLAUDE_OUT")
grep -qF "stand-in at $fake/home/.local/bin/claude got: -p say hi" <<<"$out" \
  && pass "lookup: run_claude runs the claude outside PATH" || fail "lookup: run_claude runs the claude outside PATH: $out"
# the PATH the run's shell gets, when the profile's PATH is /profile
run_path() { (PATH=/profile; . "$FIX/claude-env.sh"; echo "$PATH"); }
out=$(run_path)
[[ "$out" == "$bare:"* && "$out" == *":/profile:$fake/home/.local/bin" ]] \
  && pass "lookup: a claude outside PATH has its folder last on the run's PATH, behind the test's and the profile's" \
  || fail "lookup: a claude outside PATH has its folder last on the run's PATH, behind the test's and the profile's: $out"
(export HOME="$fake/home" PATH="$fake/onpath:$bare"; run_claude "$PROJECTS_ROOT/acme" "say hi") >/dev/null
out=$(run_path)
[[ "$out" == "$fake/onpath:$bare"* && "$out" == *":/profile" ]] \
  && pass "lookup: a claude on PATH adds no folder to the run's PATH" \
  || fail "lookup: a claude on PATH adds no folder to the run's PATH: $out"
out=$(export HOME="$fake/nohome" PATH="$bare"; run_claude "$PROJECTS_ROOT/acme" "say hi" 2>&1); code=$?
[ "$code" -eq 2 ] && grep -qF "claude is neither on PATH nor at" <<<"$out" \
  && pass "lookup: no claude stops with exit 2 and a message" || fail "lookup: no claude stops with exit 2 and a message: $code $out"

# The run's answer
jq -cn '{type: "assistant", message: {content: [{type: "text", text: "working"}]}}, {type: "result", subtype: "success", result: "the answer"}' > "$FIX/record.jsonl"
expect "answer: the result's text" "$(claude_answer "$FIX/record.jsonl")" "the answer"
jq -cn '{type: "result", subtype: "error_max_budget_usd", is_error: true, errors: ["Reached maximum budget ($1)"]}' > "$FIX/record.jsonl"
out=$(claude_answer "$FIX/record.jsonl")
expect "answer: a run without an answer gives how it ended" "$out" "claude ended without an answer: error_max_budget_usd"
expect "answer: and its error text" "$out" 'Reached maximum budget ($1)'
echo "sandbox_apply: Operation not permitted" > "$FIX/record.jsonl"
expect "answer: a run that died gives what it printed" "$(claude_answer "$FIX/record.jsonl")" "sandbox_apply: Operation not permitted"

done_testing
