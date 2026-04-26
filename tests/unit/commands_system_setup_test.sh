#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_install_dry_run_does_not_write() {
  local dir output bin_dir
  dir="$(mktemp -d)"
  bin_dir="$dir/bin"

  run_cli_capture output "$dir" install --dry-run --dir "$bin_dir"
  assert_contains "$output" "Dry-run mode"
  [[ ! -e "$bin_dir/ab" ]] || fail "dry-run install should not create a symlink"
}

test_add_repo_refuses_to_overwrite_entry_files() {
  local dir repo_dir output
  dir="$(mktemp -d)"
  repo_dir="$dir/new-repo"
  mkdir -p "$dir/backend" "$dir/frontend" "$repo_dir"
  printf '{}\n' > "$dir/backend/package.json"
  printf '{}\n' > "$dir/frontend/package.json"
  printf 'existing\n' > "$repo_dir/CLAUDE.md"
  init_hub_fixture "$dir"

  run_cli_capture output "$dir" add-repo "$repo_dir"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "already has root entry files"
}

test_install_dry_run_does_not_write
test_add_repo_refuses_to_overwrite_entry_files
