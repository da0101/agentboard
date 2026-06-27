#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_repair_dry_run_reports_stale_role_paths_without_writing() {
  local dir output before
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Read .claude/roles/INDEX.md and .claude/roles/debugger.md' > "$dir/CLAUDE.md"
  before="$(cat "$dir/CLAUDE.md")"

  run_cli_capture output "$dir" repair --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Dry-run mode"
  assert_contains "$output" "CLAUDE.md contains stale .claude/roles path(s)"
  assert_eq "$(cat "$dir/CLAUDE.md")" "$before"
}

test_repair_rewrites_role_paths_and_refreshes_runtime_ignore() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Read .claude/roles/INDEX.md and .claude/roles/debugger.md' > "$dir/CLAUDE.md"

  run_cli_capture output "$dir" repair
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Repair passed"
  assert_file_contains "$dir/CLAUDE.md" ".platform/roles/INDEX.md"
  assert_file_contains "$dir/CLAUDE.md" ".platform/roles/debugger.md"
  assert_file_not_contains "$dir/CLAUDE.md" ".claude/roles"
  assert_file_contains "$dir/.gitignore" "agentboard.hud-status.json"
}

test_doctor_repair_delegates_to_repair() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Role path: .claude/roles/product-manager.md' > "$dir/AGENTS.md"

  run_cli_capture output "$dir" doctor --repair --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab repair"
  assert_contains "$output" "AGENTS.md contains stale .claude/roles path(s)"
  assert_file_contains "$dir/AGENTS.md" ".claude/roles/product-manager.md"
}

test_repair_dry_run_reports_stale_role_paths_without_writing
test_repair_rewrites_role_paths_and_refreshes_runtime_ignore
test_doctor_repair_delegates_to_repair
