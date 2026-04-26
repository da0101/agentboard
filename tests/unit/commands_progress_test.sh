#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

setup_stream_with_branch() {
  local dir="$1" slug="${2:-login}"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream "$slug" \
      --domain auth \
      --base-branch main \
      --branch "feat/${slug}" >/dev/null
    git add .platform
    git commit -m "new-stream" >/dev/null 2>&1
    git checkout -q -b "feat/${slug}"
  )
}

test_progress_appends_diff_stat_to_stream_file() {
  local dir output
  dir="$(mktemp -d)"
  setup_stream_with_branch "$dir" "login"

  printf 'export const login = true;\n' > "$dir/login.ts"
  git -C "$dir" add login.ts
  git -C "$dir" commit -m "add login" >/dev/null 2>&1

  run_cli_capture output "$dir" progress login --note "added login.ts"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Appended progress block"
  assert_file_contains "$dir/.platform/work/login.md" "diff feat/login vs main"
  assert_file_contains "$dir/.platform/work/login.md" "login.ts"
  assert_file_contains "$dir/.platform/work/login.md" "note: added login.ts"
}

test_progress_dry_run_does_not_modify_file() {
  local dir output before after
  dir="$(mktemp -d)"
  setup_stream_with_branch "$dir" "dryrun"

  printf 'export const dryrun = true;\n' > "$dir/dryrun.ts"
  git -C "$dir" add dryrun.ts
  git -C "$dir" commit -m "add dryrun" >/dev/null 2>&1

  before="$(md5 -q "$dir/.platform/work/dryrun.md" 2>/dev/null || md5sum "$dir/.platform/work/dryrun.md" | awk '{print $1}')"
  run_cli_capture output "$dir" progress dryrun --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Would append"
  assert_contains "$output" "dryrun.ts"
  after="$(md5 -q "$dir/.platform/work/dryrun.md" 2>/dev/null || md5sum "$dir/.platform/work/dryrun.md" | awk '{print $1}')"
  [[ "$before" == "$after" ]] || fail "stream file changed during --dry-run"
}

test_progress_no_changes_is_noop() {
  local dir output
  dir="$(mktemp -d)"
  setup_stream_with_branch "$dir" "empty"

  run_cli_capture output "$dir" progress empty
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No changes"
  assert_file_not_contains "$dir/.platform/work/empty.md" "diff feat/empty vs main"
}

test_progress_base_override_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_stream_with_branch "$dir" "override"

  (
    cd "$dir"
    git checkout -q main
    git checkout -q -b staging
    printf 'export const base = 1;\n' > staging.ts
    git add staging.ts
    git commit -m "staging work" >/dev/null 2>&1
    git checkout -q feat/override
    printf 'export const override = true;\n' > override.ts
    git add override.ts
    git commit -m "override work" >/dev/null 2>&1
  )

  run_cli_capture output "$dir" progress override --base staging
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/work/override.md" "diff feat/override vs staging"
}

test_progress_missing_stream_fails() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" "initial"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" progress nonexistent
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not found"
}

test_progress_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" progress
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Usage: ab progress"
}

test_progress_appends_diff_stat_to_stream_file
test_progress_dry_run_does_not_modify_file
test_progress_no_changes_is_noop
test_progress_base_override_flag
test_progress_missing_stream_fails
test_progress_requires_slug
