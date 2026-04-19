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

test_update_skips_memory_placeholder_when_legacy_root_file_exists() {
  # Guard: if a user has legacy .platform/learnings.md at root (pre-migration),
  # `agentboard update` should NOT create an empty memory/learnings.md
  # placeholder — that would create a conflict for migrate-layout later.
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  # Simulate pre-migration layout: move memory/learnings.md back to root
  if [[ -f "$dir/.platform/memory/learnings.md" ]]; then
    mv "$dir/.platform/memory/learnings.md" "$dir/.platform/learnings.md"
    # Remove memory/ to reset
    rm -f "$dir/.platform/memory/gotchas.md" \
          "$dir/.platform/memory/playbook.md" \
          "$dir/.platform/memory/open-questions.md" \
          "$dir/.platform/memory/BACKLOG.md" \
          "$dir/.platform/memory/decisions.md" \
          "$dir/.platform/memory/log.md" 2>/dev/null || true
  fi

  run_cli_capture output "$dir" update
  assert_status "$RUN_STATUS" 0
  # Legacy root file preserved
  [[ -f "$dir/.platform/learnings.md" ]] || fail "legacy learnings.md was deleted"
  # No placeholder created (would collide with migrate-layout)
  [[ ! -f "$dir/.platform/memory/learnings.md" ]] \
    || fail "placeholder memory/learnings.md created despite legacy root file"
  # User is told to migrate first
  assert_contains "$output" "migrate-layout"
}

test_update_installs_runtime_gitignore_block() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -f "$dir/.gitignore"

  run_cli_capture output "$dir" update
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.gitignore" "# agentboard:runtime-begin"
  assert_file_contains "$dir/.gitignore" ".platform/events.jsonl"
  assert_file_contains "$dir/.gitignore" ".platform/.session-streams.tsv"
}

test_update_dry_run_leaves_files_unchanged
test_update_replaces_process_files_but_keeps_learnings
test_update_skips_memory_placeholder_when_legacy_root_file_exists
test_update_installs_runtime_gitignore_block
