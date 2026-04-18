#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

setup_daemon_fixture() {
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

# Helper: start daemon in dir, assert it started, return 0.
# Sets DAEMON_PORT as a side-effect (in the calling subshell if you use it
# inside one; set via file to cross subshell boundaries).
_daemon_start_and_wait() {
  local dir="$1"
  (cd "$dir"; "$TEST_ROOT/bin/agentboard" daemon start >/dev/null 2>&1)
  [[ -f "$dir/.platform/.daemon-port" ]] || return 1
}

_daemon_stop() {
  local dir="$1"
  (cd "$dir"; "$TEST_ROOT/bin/agentboard" daemon stop >/dev/null 2>&1) || true
}

_daemon_port() {
  local dir="$1"
  cat "$dir/.platform/.daemon-port" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Skip helpers
# ---------------------------------------------------------------------------

_node_available() {
  command -v node >/dev/null 2>&1
}

_curl_available() {
  command -v curl >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_daemon_subcommand_registered() {
  # Verify bin/agentboard sources daemon.sh
  grep -q "daemon.sh" "$TEST_ROOT/bin/agentboard" \
    || fail "bin/agentboard does not source daemon.sh"
  # Verify the dispatch case is wired
  grep -q 'daemon)' "$TEST_ROOT/bin/agentboard" \
    || fail "bin/agentboard has no 'daemon)' dispatch case"
}

test_daemon_start_requires_platform() {
  local dir output
  dir="$(mktemp -d)"
  # Deliberately do NOT init — no .platform/ present
  run_cli_capture output "$dir" daemon start
  # Must fail (non-zero exit)
  if [[ "$RUN_STATUS" -eq 0 ]]; then
    fail "daemon start should fail when .platform/ is absent (exit was 0)"
  fi
}

test_daemon_start_stop_status() {
  if ! _node_available; then
    printf 'SKIP: test_daemon_start_stop_status — node not available\n'
    return 0
  fi

  local dir output
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"

  # Start
  _daemon_start_and_wait "$dir" \
    || fail "daemon start did not create .platform/.daemon-port"

  # Status should report running
  run_cli_capture output "$dir" daemon status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "running"

  # Stop
  _daemon_stop "$dir"

  # Port file should be gone
  if [[ -f "$dir/.platform/.daemon-port" ]]; then
    fail ".platform/.daemon-port still exists after daemon stop"
  fi

  # Status should report stopped
  run_cli_capture output "$dir" daemon status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "stopped"
}

test_daemon_post_event() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_daemon_post_event — node or curl not available\n'
    return 0
  fi

  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  local port; port="$(_daemon_port "$dir")"
  [[ -n "$port" ]] || fail ".daemon-port is empty"

  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/event" \
    -H 'Content-Type: application/json' \
    -d '{"hook_event_name":"TestTool","tool_name":"Bash","test":true}')"
  assert_eq "$status" "204"

  # Give the daemon one tick to flush the write
  sleep 0.1

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created after POST /event"
  assert_file_contains "$log" '"tool_name":"Bash"'

  _daemon_stop "$dir"
}

test_daemon_get_events() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_daemon_get_events — node or curl not available\n'
    return 0
  fi

  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  local port; port="$(_daemon_port "$dir")"

  # POST a test event
  curl -s -o /dev/null -X POST "http://127.0.0.1:${port}/event" \
    -H 'Content-Type: application/json' \
    -d '{"hook_event_name":"GetEventsTest","tool_name":"Read","marker":"get_events_test"}' \
    >/dev/null
  sleep 0.1

  # GET /events — must be a JSON array
  local body
  body="$(curl -sf "http://127.0.0.1:${port}/events" 2>/dev/null)"
  assert_contains "$body" '"marker":"get_events_test"'
  # Basic JSON array check: starts with [
  [[ "${body:0:1}" == "[" ]] || fail "GET /events did not return a JSON array (got: $body)"

  _daemon_stop "$dir"
}

test_daemon_get_health() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_daemon_get_health — node or curl not available\n'
    return 0
  fi

  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  local port; port="$(_daemon_port "$dir")"

  local body
  body="$(curl -sf "http://127.0.0.1:${port}/health" 2>/dev/null)"
  assert_contains "$body" '"pid"'

  _daemon_stop "$dir"
}

test_daemon_concurrent_writes_no_corruption() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_daemon_concurrent_writes_no_corruption — node or curl not available\n'
    return 0
  fi

  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  local port; port="$(_daemon_port "$dir")"

  # Fire 20 concurrent POSTs
  local i
  for i in $(seq 1 20); do
    curl -s -o /dev/null -X POST "http://127.0.0.1:${port}/event" \
      -H 'Content-Type: application/json' \
      -d "{\"hook_event_name\":\"ConcurrentWrite\",\"tool_name\":\"Bash\",\"seq\":${i}}" &
  done
  wait

  # Give daemon a moment to flush all writes
  sleep 0.3

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"

  local line_count
  line_count="$(awk 'END { print NR }' "$log")"
  assert_eq "$line_count" "20"

  _daemon_stop "$dir"
}

test_event_logger_uses_daemon_when_running() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_event_logger_uses_daemon_when_running — node or curl not available\n'
    return 0
  fi

  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  # Invoke event-logger.sh with a test payload (it must cd to dir so .platform/ is found)
  printf '{"hook_event_name":"Test","tool_name":"Write"}' \
    | (cd "$dir"; bash "$dir/.platform/scripts/hooks/event-logger.sh")

  sleep 0.2

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created after event-logger.sh"
  local count; count="$(awk 'END { print NR }' "$log")"
  (( count >= 1 )) || fail "events.jsonl should have at least 1 line, got $count"

  _daemon_stop "$dir"
}

test_event_logger_fallback_when_no_daemon() {
  local dir
  dir="$(mktemp -d)"
  setup_daemon_fixture "$dir"
  # Deliberately do NOT start the daemon

  printf '{"hook_event_name":"FallbackTest","tool_name":"Edit"}' \
    | (cd "$dir"; bash "$dir/.platform/scripts/hooks/event-logger.sh")

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created by direct fallback"
  local count; count="$(awk 'END { print NR }' "$log")"
  (( count >= 1 )) || fail "direct fallback should have written at least 1 line, got $count"
}

test_daemon_binary_path_from_update_help() {
  local daemon_js="$TEST_ROOT/bin/agentboard-daemon.js"
  [[ -f "$daemon_js" ]] \
    || fail "bin/agentboard-daemon.js not found in agentboard repo at $daemon_js"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_daemon_subcommand_registered
test_daemon_start_requires_platform
test_daemon_start_stop_status
test_daemon_post_event
test_daemon_get_events
test_daemon_get_health
test_daemon_concurrent_writes_no_corruption
test_event_logger_uses_daemon_when_running
test_event_logger_fallback_when_no_daemon
test_daemon_binary_path_from_update_help
