#!/usr/bin/env bash
# event_logger_skill_role_test.sh — unit tests for the Skill and RoleAdopt
# event-logger.sh cases, plus fail-open malformed input behaviour.
#
# Covers:
#   1. Skill) case: PostToolUse with tool_name=Skill, subagent_type=ab-debug
#      → emits {"tool":"Skill","skill":"ab-debug",...}
#   2. RoleAdopt case: PostToolUse Read of a .platform/roles/debugger.md path
#      → emits {"tool":"RoleAdopt","role":"debugger",...}
#   3. UserPromptSubmit with /ab-debug prompt → emits Skill event (UPS path)
#   4. Both events include session_id
#   5. Fail-open: malformed JSON input exits 0 and produces no output
#   6. Completely empty input exits 0 and produces no output
#
# Run: bash tests/unit/event_logger_skill_role_test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture: minimal project with .platform + one stream so the logger can run
# ---------------------------------------------------------------------------
setup_logger_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md 2>/dev/null || true
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain eng >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-stream debug-session \
      --domain eng --base-branch main --branch feat/debug >/dev/null 2>&1
  )
}

# ROOT is tests/, so the hook is at ../templates/platform/scripts/hooks/event-logger.sh
HOOK="$(cd "$ROOT/.." && pwd)/templates/platform/scripts/hooks/event-logger.sh"

_fire() {
  local dir="$1" json="$2"
  printf '%s' "$json" | (cd "$dir"; bash "$HOOK")
}

# ---------------------------------------------------------------------------
# Test 1: Skill tool → emits Skill event with correct skill and session_id
# ---------------------------------------------------------------------------
test_skill_tool_emits_skill_event() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  _fire "$dir" '{"tool_name":"Skill","subagent_type":"ab-debug","session_id":"sess-skill-01"}'

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for Skill event"

  assert_file_contains "$log" '"tool":"Skill"'
  assert_file_contains "$log" '"skill":"ab-debug"'
  assert_file_contains "$log" '"session_id":"sess-skill-01"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 2: RoleAdopt case — Read of .platform/roles/debugger.md
# ---------------------------------------------------------------------------
test_role_adopt_from_platform_roles_read() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  # Create the roles dir and a role file so the path validation in the logger passes
  mkdir -p "$dir/.platform/roles"
  { echo "---"; echo "name: Debugger"; echo "---"; echo "# Debugger role"; } > "$dir/.platform/roles/debugger.md"

  _fire "$dir" "{\"tool_name\":\"Read\",\"file_path\":\"$dir/.platform/roles/debugger.md\",\"session_id\":\"sess-role-01\"}"

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for RoleAdopt event"

  assert_file_contains "$log" '"tool":"RoleAdopt"'
  assert_file_contains "$log" '"role":"debugger"'
  assert_file_contains "$log" '"session_id":"sess-role-01"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 3: UserPromptSubmit with /skill-name → Skill event (UPS path)
# ---------------------------------------------------------------------------
test_user_prompt_submit_skill_invocation() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  _fire "$dir" '{"hook_event_name":"UserPromptSubmit","prompt":"/ab-debug some task","session_id":"sess-ups-01"}'

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for UPS Skill event"

  assert_file_contains "$log" '"tool":"Skill"'
  assert_file_contains "$log" '"skill":"ab-debug"'
  assert_file_contains "$log" '"session_id":"sess-ups-01"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 3b: UserPromptSubmit respects AGENTBOARD_PROVIDER (Codex hooks/wrappers)
# ---------------------------------------------------------------------------
test_user_prompt_submit_skill_uses_provider_env() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"/ab-debug some task","session_id":"sess-ups-codex"}' \
    | (cd "$dir"; AGENTBOARD_PROVIDER=codex bash "$HOOK")

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for provider-tagged UPS Skill event"

  assert_file_contains "$log" '"provider":"codex"'
  assert_file_contains "$log" '"tool":"Skill"'
  assert_file_contains "$log" '"skill":"ab-debug"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 3c: Read of .agents/skills/<skill>/SKILL.md emits Skill (Codex/Gemini)
# ---------------------------------------------------------------------------
test_agents_skill_read_emits_skill_event() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  mkdir -p "$dir/.agents/skills/ab-review"
  printf '# Review\n' > "$dir/.agents/skills/ab-review/SKILL.md"

  _fire "$dir" "{\"tool_name\":\"Read\",\"file_path\":\"$dir/.agents/skills/ab-review/SKILL.md\",\"session_id\":\"sess-agent-skill\"}"

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for .agents skill read"

  assert_file_contains "$log" '"tool":"Skill"'
  assert_file_contains "$log" '"skill":"ab-review"'
  assert_file_contains "$log" '"session_id":"sess-agent-skill"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 4: UserPromptSubmit non-slash prompt → NOT logged (dropped)
# ---------------------------------------------------------------------------
test_user_prompt_submit_non_slash_is_dropped() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  _fire "$dir" '{"hook_event_name":"UserPromptSubmit","prompt":"just a normal message","session_id":"sess-ups-02"}'

  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "non-slash UPS must not write to log"

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 5: Fail-open — malformed JSON exits 0 (never blocks the tool call)
# event-logger extracts fields via awk; malformed JSON yields empty strings,
# so it may write a skeleton event with empty tool/session_id, but it must
# NEVER exit non-zero (that would block Claude's tool execution).
# ---------------------------------------------------------------------------
test_malformed_input_exits_zero() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  # Completely invalid JSON
  local status=0
  printf 'NOT JSON AT ALL {{{{' | (cd "$dir"; bash "$HOOK") || status=$?
  [[ "$status" -eq 0 ]] || fail "malformed JSON must exit 0, got $status"

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 6: Empty input exits 0, no log file created
# ---------------------------------------------------------------------------
test_empty_input_exits_zero() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  local status=0
  : | (cd "$dir"; bash "$HOOK") || status=$?
  [[ "$status" -eq 0 ]] || fail "empty input must exit 0, got $status"
  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "empty input must not create log"

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 7: Skill event includes ts (timestamp) field
# ---------------------------------------------------------------------------
test_skill_event_has_timestamp() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  _fire "$dir" '{"tool_name":"Skill","subagent_type":"ab-research","session_id":"sess-ts-01"}'

  assert_file_contains "$dir/.platform/events.jsonl" '"ts":"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 8: RoleAdopt event includes ts field
# ---------------------------------------------------------------------------
test_role_adopt_event_has_timestamp() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  mkdir -p "$dir/.platform/roles"
  { echo "---"; echo "name: Researcher"; echo "---"; } > "$dir/.platform/roles/researcher.md"

  _fire "$dir" "{\"tool_name\":\"Read\",\"file_path\":\"$dir/.platform/roles/researcher.md\",\"session_id\":\"sess-ts-02\"}"

  assert_file_contains "$dir/.platform/events.jsonl" '"ts":"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 9: Read of non-role file is NOT logged
# ---------------------------------------------------------------------------
test_read_of_regular_file_not_logged() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  _fire "$dir" '{"tool_name":"Read","file_path":"src/main.ts","session_id":"sess-read-01"}'

  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "Read of regular file must not be logged"

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Test 10: Skill tool with only "type" field (fallback) also works
# ---------------------------------------------------------------------------
test_skill_tool_type_field_fallback() {
  local dir
  dir="$(mktemp -d)"
  setup_logger_fixture "$dir"

  # When subagent_type is absent, logger falls back to "type" field
  _fire "$dir" '{"tool_name":"Skill","type":"ab-qa","session_id":"sess-skill-fallback"}'

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for Skill fallback event"

  assert_file_contains "$log" '"tool":"Skill"'
  assert_file_contains "$log" '"skill":"ab-qa"'

  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_skill_tool_emits_skill_event
test_role_adopt_from_platform_roles_read
test_user_prompt_submit_skill_invocation
test_user_prompt_submit_skill_uses_provider_env
test_agents_skill_read_emits_skill_event
test_user_prompt_submit_non_slash_is_dropped
test_malformed_input_exits_zero
test_empty_input_exits_zero
test_skill_event_has_timestamp
test_role_adopt_event_has_timestamp
test_read_of_regular_file_not_logged
test_skill_tool_type_field_fallback
