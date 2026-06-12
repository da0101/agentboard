#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

make_locks_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform"
  printf '%s' "$dir"
}

# Returns a real-but-dead pid (a background job that has already exited).
dead_pid() {
  local pid
  ( : ) &
  pid=$!
  wait "$pid" 2>/dev/null || true
  printf '%s' "$pid"
}

# Appender used by the concurrency smoke test. Runs in a background subshell;
# does a locked read-modify-write 50 times: bump a counter file (truncating
# write — the racy pattern the lock protects) and append one line.
_locks_smoke_appender() {
  local dir="$1" i=0 n
  cd "$dir"
  while (( i < 50 )); do
    platform_lock_acquire "smoke" 30 2>/dev/null || fail "smoke appender: acquire timed out"
    n="$(cat count.txt 2>/dev/null || printf '0')"
    printf '%s\n' "$(( n + 1 ))" > count.txt
    printf 'line %s\n' "$n" >> out.txt
    platform_lock_release "smoke"
    i=$(( i + 1 ))
  done
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_locks_sourced_from_core() {
  grep -q "locks.sh" "$TEST_ROOT/lib/agentboard/core.sh" \
    || fail "lib/agentboard/core.sh does not source core/locks.sh"
}

test_lock_acquire_release_roundtrip() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    platform_lock_acquire "demo" 2 || fail "acquire failed"
    [[ -d ".platform/.locks/demo.lock" ]] || fail "lock dir was not created"
    grep -qx "$$" ".platform/.locks/demo.lock/pid" \
      || fail "lock did not record \$\$ as holder pid"
    [[ -s ".platform/.locks/demo.lock/acquired_at" ]] \
      || fail "lock did not record acquired_at timestamp"
    platform_lock_release "demo"
    [[ ! -d ".platform/.locks/demo.lock" ]] || fail "release did not remove lock dir"
  )
}

test_lock_second_acquire_times_out_while_held() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    platform_lock_acquire "demo" 2 || fail "first acquire failed"
    # Holder pid ($$) is alive and the lock is fresh — second acquire must
    # time out (fail open, exit 1), not steal.
    if platform_lock_acquire "demo" 1 2>/dev/null; then
      fail "second acquire succeeded while lock was held"
    fi
    [[ -d ".platform/.locks/demo.lock" ]] || fail "held lock vanished after failed acquire"
    # Release our original hold, then the lock is acquirable again.
    platform_lock_release "demo"
    platform_lock_acquire "demo" 2 || fail "re-acquire after release failed"
    platform_lock_release "demo"
  )
}

test_lock_blocked_acquire_succeeds_after_release() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    platform_lock_acquire "demo" 2 || fail "first acquire failed"
    # Background contender blocks, then wins once we release.
    (
      cd "$dir"
      platform_lock_acquire "demo" 10 2>/dev/null || exit 1
      printf 'got\n' > contender.txt
      platform_lock_release "demo"
    ) &
    local contender=$!
    sleep 0.5
    platform_lock_release "demo"
    wait "$contender" || fail "blocked contender did not acquire after release"
    [[ -f "contender.txt" ]] || fail "contender never ran its critical section"
    [[ ! -d ".platform/.locks/demo.lock" ]] || fail "lock dir left behind"
  )
}

test_lock_stale_dead_pid_is_stolen() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    mkdir -p ".platform/.locks/demo.lock"
    printf '%s\n' "$(dead_pid)" > ".platform/.locks/demo.lock/pid"
    printf '%s\n' "$(date +%s)" > ".platform/.locks/demo.lock/acquired_at"
    printf 'foreign-token\n' > ".platform/.locks/demo.lock/token"
    platform_lock_acquire "demo" 3 || fail "stale lock (dead pid) was not stolen"
    grep -qx "$$" ".platform/.locks/demo.lock/pid" \
      || fail "stolen lock does not record the new holder pid"
    platform_lock_release "demo"
  )
}

test_lock_stale_old_lock_is_stolen() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    mkdir -p ".platform/.locks/demo.lock"
    # Holder pid is alive ($$), but the lock is older than the ~60s budget.
    printf '%s\n' "$$" > ".platform/.locks/demo.lock/pid"
    printf '%s\n' "$(( $(date +%s) - 120 ))" > ".platform/.locks/demo.lock/acquired_at"
    printf 'foreign-token\n' > ".platform/.locks/demo.lock/token"
    platform_lock_acquire "demo" 3 || fail "stale lock (older than 60s) was not stolen"
    platform_lock_release "demo"
  )
}

test_lock_with_lock_wrapper_runs_command_and_releases() {
  local dir
  dir="$(make_locks_fixture)"
  (
    cd "$dir"
    platform_with_lock "demo" touch ran.txt || fail "with-lock wrapper failed"
    [[ -f "ran.txt" ]] || fail "wrapped command did not run"
    [[ ! -d ".platform/.locks/demo.lock" ]] || fail "with-lock did not release"
    # Propagates the wrapped command's exit status.
    local status=0
    platform_with_lock "demo" false 2>/dev/null || status=$?
    assert_status "$status" 1
    [[ ! -d ".platform/.locks/demo.lock" ]] || fail "with-lock leaked lock on failure"
  )
}

test_lock_concurrency_smoke() {
  local dir
  dir="$(make_locks_fixture)"
  _locks_smoke_appender "$dir" &
  local p1=$!
  _locks_smoke_appender "$dir" &
  local p2=$!
  wait "$p1" || fail "appender 1 failed"
  wait "$p2" || fail "appender 2 failed"

  local lines count
  lines="$(wc -l < "$dir/out.txt" | tr -d ' ')"
  count="$(tr -d ' \n' < "$dir/count.txt")"
  assert_eq "$lines" "100"
  assert_eq "$count" "100"
  [[ ! -d "$dir/.platform/.locks/smoke.lock" ]] || fail "smoke lock left behind"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_locks_sourced_from_core
test_lock_acquire_release_roundtrip
test_lock_second_acquire_times_out_while_held
test_lock_blocked_acquire_succeeds_after_release
test_lock_stale_dead_pid_is_stolen
test_lock_stale_old_lock_is_stolen
test_lock_with_lock_wrapper_runs_command_and_releases
test_lock_concurrency_smoke
