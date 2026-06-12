#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

setup_log_reason_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
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

# Helper: start daemon in dir, assert it started.
_daemon_start_and_wait() {
  local dir="$1"
  (cd "$dir"; "$TEST_ROOT/bin/ab" daemon start >/dev/null 2>&1)
  [[ -f "$dir/.platform/.daemon-port" ]] || return 1
}

_daemon_stop() {
  local dir="$1"
  (cd "$dir"; "$TEST_ROOT/bin/ab" daemon stop >/dev/null 2>&1) || true
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_log_reason_subcommand_registered() {
  # Verify bin/ab sources log_reason.sh
  grep -q "log_reason.sh" "$TEST_ROOT/bin/ab" \
    || fail "bin/ab does not source log_reason.sh"
  # Verify the dispatch case is wired
  grep -q 'log-reason)' "$TEST_ROOT/bin/ab" \
    || fail "bin/ab has no 'log-reason)' dispatch case"
}

test_log_reason_writes_event_no_daemon() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  run_cli_capture output "$dir" log-reason "Refactored auth to support OAuth2"
  assert_status "$RUN_STATUS" 0

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  assert_file_contains "$log" '"hook_event_name":"Reason"'
  assert_file_contains "$log" 'Refactored auth'
}

test_log_reason_with_file_argument() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  run_cli_capture output "$dir" log-reason "src/auth.ts" "Extracted token validation into middleware"
  assert_status "$RUN_STATUS" 0

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  assert_file_contains "$log" '"file":"src/auth.ts"'
  assert_file_contains "$log" 'Extracted token validation'
}

test_log_reason_with_daemon() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_log_reason_with_daemon — node or curl not available\n'
    return 0
  fi

  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  run_cli_capture output "$dir" log-reason "Daemon-routed reason for testing"
  assert_status "$RUN_STATUS" 0

  # Give daemon a tick to flush the write
  sleep 0.2

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created after daemon-routed log-reason"
  assert_file_contains "$log" 'Daemon-routed reason'

  _daemon_stop "$dir"
}

test_log_reason_empty_reason_fails() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  run_cli_capture output "$dir" log-reason ""
  if [[ "$RUN_STATUS" -eq 0 ]]; then
    fail "log-reason with empty reason should exit non-zero (got 0)"
  fi
}

test_log_reason_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  run_cli_capture output "$dir" log-reason --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "one-sentence"
}

test_log_reason_provider_tagged() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  AGENTBOARD_PROVIDER=codex run_cli_capture output "$dir" log-reason "Provider tagging test"
  assert_status "$RUN_STATUS" 0

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  assert_file_contains "$log" '"provider":"codex"'
}

test_log_reason_ignores_stale_env_and_invalid_brief() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  local tmp
  tmp="$(mktemp)"
  awk '
    { gsub(/\*\*Feature:\*\* login/, "**Feature:** platform-hardening") }
    { gsub(/\*\*Stream file:\*\* `work\/login\.md`/, "**Stream file:** `work/platform-hardening.md`") }
    { print }
  ' "$dir/.platform/work/BRIEF.md" > "$tmp"
  mv "$tmp" "$dir/.platform/work/BRIEF.md"

  AGENTBOARD_STREAM=platform-hardening run_cli_capture output "$dir" log-reason "Stale stream fallback test"
  assert_status "$RUN_STATUS" 0

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  assert_file_contains "$log" '"stream":"login"'
}

test_log_reason_prefers_stream_file_argument() {
  local dir output
  dir="$(mktemp -d)"
  setup_log_reason_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain billing >/dev/null
    "$TEST_ROOT/bin/ab" new-stream billing-fix \
      --domain billing --base-branch main --branch feat/billing >/dev/null
  )

  local tmp
  tmp="$(mktemp)"
  awk '
    { gsub(/\*\*Feature:\*\* login/, "**Feature:** platform-hardening") }
    { gsub(/\*\*Stream file:\*\* `work\/login\.md`/, "**Stream file:** `work/platform-hardening.md`") }
    { print }
  ' "$dir/.platform/work/BRIEF.md" > "$tmp"
  mv "$tmp" "$dir/.platform/work/BRIEF.md"

  AGENTBOARD_STREAM=platform-hardening run_cli_capture output "$dir" log-reason \
    ".platform/work/billing-fix.md" \
    "Billing audit anchored in stream file"
  assert_status "$RUN_STATUS" 0

  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  assert_file_contains "$log" '"stream":"billing-fix"'
  assert_file_contains "$log" '"file":".platform/work/billing-fix.md"'
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_log_reason_subcommand_registered
test_log_reason_writes_event_no_daemon
test_log_reason_with_file_argument
test_log_reason_with_daemon
test_log_reason_empty_reason_fails
test_log_reason_help
test_log_reason_provider_tagged
test_log_reason_ignores_stale_env_and_invalid_brief
test_log_reason_prefers_stream_file_argument
