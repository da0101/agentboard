#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

setup_rotation_fixture() {
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

# Write N lines to events.jsonl in dir
_write_events() {
  local dir="$1" n="$2"
  local log="$dir/.platform/events.jsonl"
  local i
  for i in $(seq 1 "$n"); do
    printf '{"ts":"2026-04-18T00:00:0%sZ","tool":"Bash","seq":%s}\n' "$((i % 10))" "$i" >> "$log"
  done
}

# Count non-blank lines in a file
_line_count() {
  awk 'NF' "$1" | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_events_rotate_subcommand_exists() {
  grep -q 'rotate)' "$TEST_ROOT/lib/agentboard/commands/events.sh" \
    || fail "events.sh does not have a 'rotate)' case"
}

test_events_rotate_below_threshold_no_force() {
  local dir output
  dir="$(mktemp -d)"
  setup_rotation_fixture "$dir"
  _write_events "$dir" 10

  run_cli_capture output "$dir" events rotate
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "threshold"

  # File should still have 10 lines — not rotated
  local count; count="$(_line_count "$dir/.platform/events.jsonl")"
  assert_eq "$count" "10"
}

test_events_rotate_force() {
  local dir output
  dir="$(mktemp -d)"
  setup_rotation_fixture "$dir"
  _write_events "$dir" 10

  run_cli_capture output "$dir" events rotate --force
  assert_status "$RUN_STATUS" 0

  # Live file must be truncated (0 lines)
  local count; count="$(_line_count "$dir/.platform/events.jsonl")"
  assert_eq "$count" "0"

  # An archive file must exist
  local archives
  archives="$(ls "$dir/.platform"/events-*.jsonl 2>/dev/null || true)"
  [[ -n "$archives" ]] || fail "No archive file created after --force rotate"
}

test_events_archive_lists_files() {
  local dir output
  dir="$(mktemp -d)"
  setup_rotation_fixture "$dir"

  # Create a fake archive file
  local archive="$dir/.platform/events-2026-01-01.jsonl"
  printf '{"ts":"2026-01-01T00:00:00Z","tool":"Bash"}\n' > "$archive"
  printf '{"ts":"2026-01-01T00:00:01Z","tool":"Edit"}\n' >> "$archive"
  printf '{"ts":"2026-01-01T00:00:02Z","tool":"Grep"}\n' >> "$archive"
  printf '{"ts":"2026-01-01T00:00:03Z","tool":"Read"}\n' >> "$archive"
  printf '{"ts":"2026-01-01T00:00:04Z","tool":"Write"}\n' >> "$archive"

  run_cli_capture output "$dir" events archive
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "events-2026-01-01"
}

test_events_rotate_threshold_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_rotation_fixture "$dir"
  _write_events "$dir" 3

  run_cli_capture output "$dir" events rotate --threshold 2
  assert_status "$RUN_STATUS" 0

  # 3 lines > threshold of 2, so must have rotated
  local count; count="$(_line_count "$dir/.platform/events.jsonl")"
  assert_eq "$count" "0"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_events_rotate_subcommand_exists
test_events_rotate_below_threshold_no_force
test_events_rotate_force
test_events_archive_lists_files
test_events_rotate_threshold_flag
