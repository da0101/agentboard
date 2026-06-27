#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_codex_hook_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  mkdir -p "$dir/src"
  printf 'export const x = 1;\n' > "$dir/src/main.ts"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md >/dev/null 2>&1 || true
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain eng >/dev/null
    "$TEST_ROOT/bin/ab" new-stream codex-work \
      --domain eng --base-branch main --branch feat/codex >/dev/null
  )
}

BRIDGE="$TEST_ROOT/templates/platform/scripts/hooks/codex-hook-bridge.js"

test_codex_post_tool_use_writes_session_and_event() {
  local dir home
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  setup_codex_hook_fixture "$dir"

  printf '%s' '{"session_id":"codex-native-1","tool_name":"Write","file_path":"src/main.ts","model":"gpt-5.4"}' \
    | (cd "$dir"; HOME="$home" AGENTBOARD_PROVIDER=codex AGENTBOARD_CODEX_HOOK_EVENT=PostToolUse node "$BRIDGE")

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created by Codex hook bridge"
  assert_file_contains "$log" '"provider":"codex"'
  assert_file_contains "$log" '"tool":"Write"'
  assert_file_contains "$log" '"file":"src/main.ts"'
  assert_file_contains "$log" '"session_id":"codex-native-1"'

  local session_json="$home/.agentboard/sessions/codex-native-1.json"
  [[ -f "$session_json" ]] || fail "session JSON not created by Codex hook bridge"
  assert_file_contains "$session_json" '"provider": "codex"'
  assert_file_contains "$session_json" '"_session_id": "codex-native-1"'
  assert_file_contains "$session_json" '"model": "gpt-5.4"'
}

test_codex_subagent_hooks_emit_agent_events() {
  local dir home
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  setup_codex_hook_fixture "$dir"

  printf '%s' '{"session_id":"codex-native-2","subagent_type":"researcher"}' \
    | (cd "$dir"; HOME="$home" AGENTBOARD_PROVIDER=codex AGENTBOARD_CODEX_HOOK_EVENT=SubagentStart node "$BRIDGE")
  printf '%s' '{"session_id":"codex-native-2","subagent_type":"researcher"}' \
    | (cd "$dir"; HOME="$home" AGENTBOARD_PROVIDER=codex AGENTBOARD_CODEX_HOOK_EVENT=SubagentStop node "$BRIDGE")

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for Codex subagent hooks"
  assert_file_contains "$log" '"tool":"AgentStart"'
  assert_file_contains "$log" '"tool":"AgentDone"'
  assert_file_contains "$log" '"label":"researcher"'
  assert_file_contains "$log" '"session_id":"codex-native-2"'
}

test_codex_post_tool_use_writes_session_and_event
test_codex_subagent_hooks_emit_agent_events
