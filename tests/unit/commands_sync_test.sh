#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_sync_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
}

test_sync_check_detects_drift_after_init() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  # After init, AGENTS.md/GEMINI.md are scaffold stubs that diverge from
  # what sync-context.sh would generate from CLAUDE.md → expect drift.
  run_cli_capture output "$dir" sync
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "DRIFT"
  assert_contains "$output" "ab sync --apply"
}

test_sync_apply_resolves_drift() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  run_cli_capture output "$dir" sync --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Synced"
  # Second check should now pass
  run_cli_capture output "$dir" sync
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "All entry files in sync"
}

test_sync_dry_run_alias_shows_drift_without_writing() {
  local dir output before_agents after_agents
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  before_agents="$(cat "$dir/AGENTS.md")"
  run_cli_capture output "$dir" sync --dry-run
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "DRIFT"
  after_agents="$(cat "$dir/AGENTS.md")"
  [[ "$before_agents" == "$after_agents" ]] || fail "sync --dry-run must not modify AGENTS.md"
}

test_sync_list_shows_repo() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  run_cli_capture output "$dir" sync --list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "will operate on these repos"
}

test_sync_rejects_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  run_cli_capture output "$dir" sync --bogus
  [[ "$RUN_STATUS" -ne 0 ]] || fail "expected non-zero exit for unknown flag"
  assert_contains "$output" "unknown flag"
}

test_sync_missing_platform_points_to_init() {
  local dir output
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" sync
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No .platform/ found"
  assert_contains "$output" "ab init"
}

test_sync_missing_script_points_to_update() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  rm -f "$dir/.platform/scripts/sync-context.sh"
  run_cli_capture output "$dir" sync
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" ".platform/scripts/sync-context.sh is missing"
  assert_contains "$output" "ab update"
  assert_not_contains "$output" "./.platform/scripts/sync-context.sh not found"
}

test_sync_non_executable_script_points_to_update() {
  local dir output
  dir="$(mktemp -d)"
  setup_sync_fixture "$dir"
  chmod -x "$dir/.platform/scripts/sync-context.sh"
  run_cli_capture output "$dir" sync
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" ".platform/scripts/sync-context.sh is not executable"
  assert_contains "$output" "ab update"
}

test_sync_check_detects_drift_after_init
test_sync_apply_resolves_drift
test_sync_dry_run_alias_shows_drift_without_writing
test_sync_list_shows_repo
test_sync_rejects_unknown_flag
test_sync_missing_platform_points_to_init
test_sync_missing_script_points_to_update
test_sync_non_executable_script_points_to_update
