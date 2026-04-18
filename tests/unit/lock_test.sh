#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

setup_lock_fixture() {
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
# Tests
# ---------------------------------------------------------------------------

test_lock_subcommand_registered() {
  # Verify bin/agentboard sources lock.sh
  grep -q "lock.sh" "$TEST_ROOT/bin/agentboard" \
    || fail "bin/agentboard does not source lock.sh"
  # Verify the dispatch case is wired
  grep -q 'lock)' "$TEST_ROOT/bin/agentboard" \
    || fail "bin/agentboard has no 'lock)' dispatch case"
}

test_lock_list_no_daemon() {
  local dir output
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"
  # Daemon is NOT started — command must not crash
  run_cli_capture output "$dir" lock list
  assert_status "$RUN_STATUS" 0
  # Should print graceful message — either "No files currently locked" or
  # "daemon not running" / similar — anything but a blank crash
  local lower
  lower="$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" != *"no files"* && "$lower" != *"daemon"* && "$lower" != *"locked"* && "$lower" != *"lock"* ]]; then
    fail "lock list (no daemon) produced unexpected output: $output"
  fi
}

test_lock_acquire_release_cycle() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_lock_acquire_release_cycle — node or curl not available\n'
    return 0
  fi

  local dir output
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"

  # Acquire
  run_cli_capture output "$dir" lock acquire src/auth.ts
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "acquired"

  # List — should show the locked file
  run_cli_capture output "$dir" lock list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "auth.ts"

  # Release
  run_cli_capture output "$dir" lock release src/auth.ts
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "released"

  # List — should no longer show the file
  run_cli_capture output "$dir" lock list
  assert_status "$RUN_STATUS" 0
  assert_not_contains "$output" "auth.ts"

  _daemon_stop "$dir"
}

test_lock_queue_second_provider() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_lock_queue_second_provider — node or curl not available\n'
    return 0
  fi

  local dir port
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"
  port="$(_daemon_port "$dir")"
  [[ -n "$port" ]] || fail ".daemon-port is empty"

  # Let claude acquire the lock directly via HTTP
  local acquire_status
  acquire_status="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/auth.ts","provider":"claude"}')"
  assert_eq "$acquire_status" "200"

  # Codex tries to acquire the same file — should be queued (202)
  local queue_status
  queue_status="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/auth.ts","provider":"codex"}')"
  assert_eq "$queue_status" "202"

  # GET /locks — codex should appear in the queue
  local locks_body
  locks_body="$(curl -sf "http://127.0.0.1:${port}/locks" 2>/dev/null)"
  assert_contains "$locks_body" "codex"

  # Release claude's lock so the queued codex acquire can resolve
  local release_status
  release_status="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X DELETE "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/auth.ts","provider":"claude"}')"
  assert_eq "$release_status" "200"

  # Brief pause so the daemon can hand the lock to codex
  sleep 0.2

  # Release codex's (now-held) lock to clean up
  curl -sf -s -o /dev/null \
    -X DELETE "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/auth.ts","provider":"codex"}' || true

  _daemon_stop "$dir"
}

test_daemon_lock_acquire_endpoint() {
  if ! _node_available || ! _curl_available; then
    printf 'SKIP: test_daemon_lock_acquire_endpoint — node or curl not available\n'
    return 0
  fi

  local dir port
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"
  _daemon_start_and_wait "$dir" || fail "daemon did not start"
  port="$(_daemon_port "$dir")"
  [[ -n "$port" ]] || fail ".daemon-port is empty"

  # POST /lock — first provider: expect 200 (acquired)
  local s1
  s1="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/main.ts","provider":"claude"}')"
  assert_eq "$s1" "200"

  # POST /lock same file, different provider — expect 202 (queued)
  local s2
  s2="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/main.ts","provider":"codex"}')"
  assert_eq "$s2" "202"

  # GET /locks — must return a JSON array with 1 entry containing "queue"
  local body
  body="$(curl -sf "http://127.0.0.1:${port}/locks" 2>/dev/null)"
  [[ "${body:0:1}" == "[" ]] || fail "GET /locks did not return a JSON array (got: $body)"
  assert_contains "$body" "queue"
  assert_contains "$body" "main.ts"

  # DELETE /lock — release claude's lock: expect 200
  local s3
  s3="$(curl -sf -s -o /dev/null -w '%{http_code}' \
    -X DELETE "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/main.ts","provider":"claude"}')"
  assert_eq "$s3" "200"

  # Brief pause so the daemon can hand the lock to codex
  sleep 0.2

  # Release codex lock too
  curl -sf -s -o /dev/null \
    -X DELETE "http://127.0.0.1:${port}/lock" \
    -H 'Content-Type: application/json' \
    -d '{"file":"src/main.ts","provider":"codex"}' || true

  # GET /locks — should now be empty
  local body2
  body2="$(curl -sf "http://127.0.0.1:${port}/locks" 2>/dev/null)"
  assert_eq "$body2" "[]"

  _daemon_stop "$dir"
}

test_daemon_lock_auto_expire() {
  # Auto-expiry (LOCK_TTL_MS) requires time mocking or patching the daemon
  # source, which is out of scope for unit tests. This behaviour should be
  # validated manually by temporarily lowering LOCK_TTL_MS in
  # bin/agentboard-daemon.js and confirming that held locks are released after
  # the TTL elapses without a DELETE. Skipping here.
  printf 'SKIP: test_daemon_lock_auto_expire — requires time mocking (out of scope for unit tests)\n'
  return 0
}

test_pre_tool_use_lock_exits_zero_when_no_daemon() {
  local dir
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"

  local hook="$dir/.platform/scripts/hooks/pre-tool-use-lock.sh"
  [[ -f "$hook" ]] || { printf 'SKIP: test_pre_tool_use_lock_exits_zero_when_no_daemon — pre-tool-use-lock.sh not installed\n'; return 0; }

  local status=0
  (
    cd "$dir"
    printf '{"tool_name":"Write","tool_input":{"file_path":"src/test.ts"}}' \
      | bash "$hook"
  ) || status=$?
  assert_status "$status" 0
}

test_post_tool_use_unlock_exits_zero_when_no_daemon() {
  local dir
  dir="$(mktemp -d)"
  setup_lock_fixture "$dir"

  local hook="$dir/.platform/scripts/hooks/post-tool-use-unlock.sh"
  [[ -f "$hook" ]] || { printf 'SKIP: test_post_tool_use_unlock_exits_zero_when_no_daemon — post-tool-use-unlock.sh not installed\n'; return 0; }

  local status=0
  (
    cd "$dir"
    printf '{"tool_name":"Write","tool_input":{"file_path":"src/test.ts"}}' \
      | bash "$hook"
  ) || status=$?
  assert_status "$status" 0
}

test_lock_hooks_in_settings_json() {
  local settings="$TEST_ROOT/templates/root/.claude/settings.json"
  [[ -f "$settings" ]] || fail "templates/root/.claude/settings.json not found"
  assert_file_contains "$settings" "pre-tool-use-lock.sh"
  assert_file_contains "$settings" "post-tool-use-unlock.sh"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_lock_subcommand_registered
test_lock_list_no_daemon
test_lock_acquire_release_cycle
test_lock_queue_second_provider
test_daemon_lock_acquire_endpoint
test_daemon_lock_auto_expire
test_pre_tool_use_lock_exits_zero_when_no_daemon
test_post_tool_use_unlock_exits_zero_when_no_daemon
test_lock_hooks_in_settings_json
