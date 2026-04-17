#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_update_dry_run_leaves_files_unchanged() {
  local dir output before
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  before="$(cat "$dir/.platform/workflow.md")"
  run_cli_capture output "$dir" update --dry-run
  assert_contains "$output" "Dry-run mode"
  assert_eq "$(cat "$dir/.platform/workflow.md")" "$before"
}

test_update_replaces_process_files_but_keeps_learnings() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  printf 'legacy workflow marker\n' >> "$dir/.platform/workflow.md"
  printf 'custom learning\n' > "$dir/.platform/memory/learnings.md"

  run_cli_capture output "$dir" update
  assert_contains "$output" "Update complete"
  assert_file_not_contains "$dir/.platform/workflow.md" "legacy workflow marker"
  assert_file_contains "$dir/.platform/memory/learnings.md" "custom learning"
}

test_update_dry_run_leaves_files_unchanged
test_update_replaces_process_files_but_keeps_learnings
