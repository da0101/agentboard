#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# migrate-layout should be safe to run on a fresh init (already correct layout)
# and should move legacy root-level memory files into .platform/memory/.

setup_legacy_fixture() {
  local dir="$1"
  mkdir -p "$dir/.platform/sessions"
  local f
  for f in decisions learnings log gotchas playbook open-questions BACKLOG; do
    printf 'old %s content\n' "$f" > "$dir/.platform/$f.md"
  done
}

test_dry_run_moves_nothing() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Dry run"
  assert_contains "$output" "decisions.md → "
  # Legacy files still at old location, nothing in memory/
  [[ -f "$dir/.platform/decisions.md" ]] || fail "dry-run moved decisions.md"
  [[ ! -d "$dir/.platform/memory" ]] || fail "dry-run created memory/"
  [[ -d "$dir/.platform/sessions" ]] || fail "dry-run removed sessions/"
}

test_apply_moves_all_memory_files() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Migration applied"

  local f
  for f in decisions learnings log gotchas playbook open-questions BACKLOG; do
    [[ ! -f "$dir/.platform/$f.md" ]] || fail "$f.md still at root after --apply"
    [[ -f "$dir/.platform/memory/$f.md" ]] || fail "$f.md not moved into memory/"
  done
  assert_file_contains "$dir/.platform/memory/decisions.md" "old decisions content"
}

test_apply_removes_empty_sessions() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -d "$dir/.platform/sessions" ]] || fail "empty sessions/ was not removed"
}

test_apply_keeps_non_empty_sessions() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  printf 'user content\n' > "$dir/.platform/sessions/some-file.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  [[ -d "$dir/.platform/sessions" ]] || fail "non-empty sessions/ was removed"
  [[ -f "$dir/.platform/sessions/some-file.md" ]] || fail "sessions file deleted"
}

test_idempotent_apply_is_noop() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  # Run again — should do nothing
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already current"
}

test_dry_run_on_clean_layout_is_clean() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/memory"
  run_cli_capture output "$dir" migrate-layout
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already current"
}

test_handles_both_old_and_new_present() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  mkdir -p "$dir/.platform/memory"
  printf 'new content\n' > "$dir/.platform/memory/decisions.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "both present"
  # Old file kept in place to avoid data loss
  [[ -f "$dir/.platform/decisions.md" ]] || fail "old decisions.md deleted despite conflict"
  assert_file_contains "$dir/.platform/memory/decisions.md" "new content"
}

test_help() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform"
  run_cli_capture output "$dir" migrate-layout --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard migrate-layout"
  assert_contains "$output" "memory/"
}

for t in \
  test_dry_run_moves_nothing \
  test_apply_moves_all_memory_files \
  test_apply_removes_empty_sessions \
  test_apply_keeps_non_empty_sessions \
  test_idempotent_apply_is_noop \
  test_dry_run_on_clean_layout_is_clean \
  test_handles_both_old_and_new_present \
  test_help; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
