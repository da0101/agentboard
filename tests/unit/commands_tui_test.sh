#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_project_with_streams() {
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
    "$TEST_ROOT/bin/agentboard" new-stream signup \
      --domain auth --base-branch main --branch feat/signup \
      --agent claude >/dev/null
  )
}

test_tui_no_platform_fails() {
  local dir output
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" tui
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No .platform/ found"
}

test_tui_renders_header_and_rows() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "STREAM"
  assert_contains "$output" "BRANCH"
  assert_contains "$output" "login"
  assert_contains "$output" "signup"
  assert_contains "$output" "feat/login"
  assert_contains "$output" "feat/signup"
}

test_tui_filter_status_matches_none_shows_empty() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --status in-progress
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "(no streams match)"
  assert_not_contains "$output" "feat/login"
}

test_tui_filter_owner_narrows_rows() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --owner claude
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "signup"
  assert_not_contains "$output" "login "
}

test_tui_filter_repo_matches_primary() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --repo repo-primary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "login"
  assert_contains "$output" "signup"
}

test_tui_filter_repo_unknown_is_empty() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --repo nonexistent-repo
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "(no streams match)"
}

test_tui_sort_flag_accepts_valid_values() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --sort branch
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "STREAM"
}

test_tui_sort_flag_rejects_invalid_values() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --sort bogus
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown --sort key"
}

test_tui_rejects_nonnumeric_watch() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --watch abc
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires an integer"
}

test_tui_help_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_project_with_streams "$dir"

  run_cli_capture output "$dir" tui --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard tui"
  assert_contains "$output" "--watch"
}

test_tui_no_platform_fails
test_tui_renders_header_and_rows
test_tui_filter_status_matches_none_shows_empty
test_tui_filter_owner_narrows_rows
test_tui_filter_repo_matches_primary
test_tui_filter_repo_unknown_is_empty
test_tui_sort_flag_accepts_valid_values
test_tui_sort_flag_rejects_invalid_values
test_tui_rejects_nonnumeric_watch
test_tui_help_flag
