#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_events_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

_fire_event() {
  local dir="$1" json="$2"
  printf '%s' "$json" | (cd "$dir"; bash "$dir/.platform/scripts/hooks/event-logger.sh")
}

# Generic "code file edited" event — always logged (non-.platform/, non-Read).
_fire_write_event() {
  local dir="$1" file="${2:-src/foo.ts}"
  _fire_event "$dir" "{\"tool_name\":\"Write\",\"file_path\":\"$file\"}"
}

test_event_logger_writes_valid_jsonl() {
  local dir
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"

  # git commit Bash events are logged; plain code edits are logged.
  _fire_event "$dir" '{"tool_name":"Bash","command":"git commit -m test"}'
  _fire_event "$dir" '{"tool_name":"Edit","file_path":"src/x.ts"}'

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"

  local line_count
  line_count="$(awk 'END { print NR }' "$log")"
  assert_eq "$line_count" "2"

  assert_file_contains "$log" '"tool":"Bash"'
  assert_file_contains "$log" '"tool":"Edit"'
  assert_file_contains "$log" '"stream":"login"'
}

test_event_logger_skips_plain_bash_and_reads() {
  local dir
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"

  # Plain Bash (not git commit/push) — must not be logged.
  _fire_event "$dir" '{"tool_name":"Bash","command":"ls -la"}'
  # Read events — must not be logged.
  _fire_event "$dir" '{"tool_name":"Read","file_path":"src/foo.ts"}'
  # .platform/ edits — must not be logged.
  _fire_event "$dir" '{"tool_name":"Edit","file_path":".platform/memory/log.md"}'

  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "noise events must not create log"
}

test_event_logger_tags_events_with_active_stream() {
  local dir
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir"
  assert_file_contains "$dir/.platform/events.jsonl" '"stream":"login"'
}

test_event_logger_prefers_session_mapping_over_first_stream() {
  local dir
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain billing >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream billing-fix \
      --domain billing --base-branch main --branch feat/billing >/dev/null
    "$TEST_ROOT/bin/agentboard" current-stream --stream billing-fix --session-id sess-42 --remember --quiet >/dev/null
  )
  _fire_event "$dir" '{"session_id":"sess-42","tool_name":"Write","file_path":"src/billing.ts"}'
  assert_file_contains "$dir/.platform/events.jsonl" '"stream":"billing-fix"'
}

test_event_logger_skips_empty_input() {
  local dir
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  : | (cd "$dir"; bash "$dir/.platform/scripts/hooks/event-logger.sh")
  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "empty input must not create log"
}

test_events_tail_shows_recent() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  # Fire 3 events; tail -n 2 should show only the last two.
  _fire_write_event "$dir" "src/a.ts"
  _fire_event "$dir" '{"tool_name":"Edit","file_path":"src/b.ts"}'
  _fire_event "$dir" '{"tool_name":"Grep"}'

  run_cli_capture output "$dir" events tail -n 2
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Edit"
  assert_contains "$output" "Grep"
  assert_not_contains "$output" "src/a.ts"
}

test_events_tail_json_mode_is_raw_jsonl() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_event "$dir" '{"tool_name":"Bash","command":"git commit -m test"}'

  run_cli_capture output "$dir" events tail -n 1 --json
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" '"tool":"Bash"'
  assert_contains "$output" '"ts":'
}

test_events_stream_filter_by_slug() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir"

  run_cli_capture output "$dir" events stream login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "login"
  assert_contains "$output" "Write"

  run_cli_capture output "$dir" events stream nonexistent
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no matching events"
}

test_events_since_filters_by_timestamp() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir"

  run_cli_capture output "$dir" events since 2099-01-01T00:00:00Z
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no matching events"

  run_cli_capture output "$dir" events since 2020-01-01T00:00:00Z
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Write"
}

test_events_stats_reports_counts_and_top_tools() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir" "src/a.ts"
  _fire_write_event "$dir" "src/b.ts"
  _fire_event "$dir" '{"tool_name":"Edit","file_path":"src/c.ts"}'

  run_cli_capture output "$dir" events stats
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "events:  3"
  assert_contains "$output" "Write"
  assert_contains "$output" "Edit"
}

test_events_clear_preview_does_not_delete() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir"

  run_cli_capture output "$dir" events clear
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Preview only"
  [[ -f "$dir/.platform/events.jsonl" ]] || fail "preview must not delete log"
}

test_events_clear_confirm_archives() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  _fire_write_event "$dir"

  run_cli_capture output "$dir" events clear --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Archived"
  [[ ! -f "$dir/.platform/events.jsonl" ]] || fail "log must be moved after --confirm"
  ls "$dir/.platform"/events.jsonl.archive-* >/dev/null 2>&1 \
    || fail "archive file not created"
}

test_events_path_prints_log_location() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  run_cli_capture output "$dir" events path
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" ".platform/events.jsonl"
}

test_events_help_output() {
  local dir output
  dir="$(mktemp -d)"
  setup_events_fixture "$dir"
  run_cli_capture output "$dir" events --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard events"
  assert_contains "$output" "tail"
  assert_contains "$output" "stream"
}

test_claude_settings_template_wires_event_logger() {
  local settings="$TEST_ROOT/templates/root/.claude/settings.json"
  [[ -f "$settings" ]] || fail "settings.json template missing"
  grep -q "PostToolUse" "$settings" \
    || fail "PostToolUse hook not registered in settings.json template"
  grep -q "event-logger.sh" "$settings" \
    || fail "event-logger.sh not referenced in settings.json template"
}

test_event_logger_writes_valid_jsonl
test_event_logger_skips_plain_bash_and_reads
test_event_logger_tags_events_with_active_stream
test_event_logger_prefers_session_mapping_over_first_stream
test_event_logger_skips_empty_input
test_events_tail_shows_recent
test_events_tail_json_mode_is_raw_jsonl
test_events_stream_filter_by_slug
test_events_since_filters_by_timestamp
test_events_stats_reports_counts_and_top_tools
test_events_clear_preview_does_not_delete
test_events_clear_confirm_archives
test_events_path_prints_log_location
test_events_help_output
test_claude_settings_template_wires_event_logger
