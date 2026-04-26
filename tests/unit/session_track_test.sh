#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_track_fixture() {
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

test_session_track_helper_installed() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  [[ -x "$dir/.platform/scripts/session-track.sh" ]] \
    || fail "session-track.sh not installed by init"
}

test_session_event_writes_jsonl_line() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  (
    cd "$dir"
    export AGENTBOARD_STREAM="login"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    _ab_session_event "SessionStart" "codex-test-1" '"provider":"codex"'
    _ab_session_event "SessionEnd" "codex-test-1" '"provider":"codex","exit_code":0'
  )
  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created"
  local count; count="$(awk 'END { print NR }' "$log")"
  assert_eq "$count" "2"
  assert_file_contains "$log" '"hook_event_name":"SessionStart"'
  assert_file_contains "$log" '"hook_event_name":"SessionEnd"'
  assert_file_contains "$log" 'codex-test-1'
  assert_file_contains "$log" '"stream":"login"'
}

test_file_poller_logs_changed_tracked_files() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  local pid
  (
    cd "$dir"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    pid="$(_ab_start_file_poller "test-session" "codex" 1)"
    # Introduce a tracked-file change
    printf 'change\n' >> package.json
    # Wait for at least one poll cycle
    sleep 2
    _ab_stop_file_poller "$pid"
  )
  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created by poller"
  assert_file_contains "$log" '"hook_event_name":"FileChange"'
  assert_file_contains "$log" '"file_path":"package.json"'
  assert_file_contains "$log" '"session_id":"test-session"'
}

test_file_poller_stops_cleanly() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  local pid
  (
    cd "$dir"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    pid="$(_ab_start_file_poller "test-session" "codex" 1)"
    # Verify the poller is alive
    kill -0 "$pid" 2>/dev/null || { echo "poller did not start"; exit 1; }
    _ab_stop_file_poller "$pid"
    # Now it should be gone
    if kill -0 "$pid" 2>/dev/null; then
      echo "poller still alive after stop"
      exit 1
    fi
  )
}

test_file_poller_dedupes_across_concurrent_sessions() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  (
    cd "$dir"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    pid1="$(_ab_start_file_poller "test-session-1" "codex" 1)"
    pid2="$(_ab_start_file_poller "test-session-2" "codex" 1)"
    printf 'change\n' >> package.json
    sleep 3
    _ab_stop_file_poller "$pid1"
    _ab_stop_file_poller "$pid2"
  )
  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created by concurrent pollers"
  local count
  count="$(grep -c '"file_path":"package.json"' "$log" || true)"
  assert_eq "$count" "1"
}

test_file_poller_relogs_same_file_after_new_diff() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  (
    cd "$dir"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    pid="$(_ab_start_file_poller "test-session" "codex" 1)"
    printf 'change-1\n' >> package.json
    sleep 2
    printf 'change-2\n' >> package.json
    sleep 2
    _ab_stop_file_poller "$pid"
  )
  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for repeat-diff test"
  local count
  count="$(grep -c '"file_path":"package.json"' "$log" || true)"
  assert_eq "$count" "2"
}

test_file_poller_clears_state_after_file_returns_clean() {
  local dir
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  (
    cd "$dir"
    # shellcheck disable=SC1091
    . "$dir/.platform/scripts/session-track.sh"
    pid="$(_ab_start_file_poller "test-session" "codex" 1)"
    printf 'change\n' >> package.json
    sleep 2
    git checkout -- package.json >/dev/null 2>&1
    sleep 2
    printf 'change\n' >> package.json
    sleep 2
    _ab_stop_file_poller "$pid"
  )
  local log="$dir/.platform/events.jsonl"
  [[ -f "$log" ]] || fail "events.jsonl not created for clean-roundtrip test"
  local count
  count="$(grep -c '"file_path":"package.json"' "$log" || true)"
  assert_eq "$count" "2"
}

test_wrappers_reference_session_track() {
  local codex="$TEST_ROOT/templates/platform/scripts/codex-ab"
  local gemini="$TEST_ROOT/templates/platform/scripts/gemini-ab"
  grep -q "session-track.sh" "$codex" \
    || fail "codex-ab does not source session-track.sh"
  grep -q "session-track.sh" "$gemini" \
    || fail "gemini-ab does not source session-track.sh"
  grep -q "SessionStart" "$codex" \
    || fail "codex-ab does not emit SessionStart event"
  grep -q "SessionEnd" "$codex" \
    || fail "codex-ab does not emit SessionEnd event"
}

test_update_refreshes_wrappers_and_tracker() {
  local dir output
  dir="$(mktemp -d)"
  setup_track_fixture "$dir"
  # Simulate stale wrapper by overwriting it with dummy content
  printf '#!/usr/bin/env bash\necho "old version"\n' > "$dir/.platform/scripts/codex-ab"
  run_cli_capture output "$dir" update
  assert_status "$RUN_STATUS" 0
  grep -q "session-track.sh" "$dir/.platform/scripts/codex-ab" \
    || fail "update did not refresh codex-ab to latest template"
  [[ -x "$dir/.platform/scripts/session-track.sh" ]] \
    || fail "update did not install session-track.sh"
}

test_session_track_helper_installed
test_session_event_writes_jsonl_line
test_file_poller_logs_changed_tracked_files
test_file_poller_stops_cleanly
test_file_poller_dedupes_across_concurrent_sessions
test_file_poller_relogs_same_file_after_new_diff
test_file_poller_clears_state_after_file_returns_clean
test_wrappers_reference_session_track
test_update_refreshes_wrappers_and_tracker
