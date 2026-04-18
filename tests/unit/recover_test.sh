#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_recover_fixture() {
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
    git add .platform
    git commit -m "new stream" >/dev/null 2>&1
    git checkout -q -b feat/login
  )
}

# Backdate the stream's updated_at so 'recover' has a window to scan.
_stale_stream() {
  local dir="$1" slug="$2"
  local sf="$dir/.platform/work/${slug}.md"
  local tmp; tmp="$(mktemp)"
  awk '/^updated_at:/ { print "updated_at: 2026-01-01"; next } { print }' "$sf" > "$tmp" && mv "$tmp" "$sf"
}

test_recover_preview_does_not_write() {
  local dir output before
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  (
    cd "$dir"
    printf 'a\n' >> package.json
    git add -A
    git commit -m "work-done" >/dev/null 2>&1
  )
  # Backdate AFTER the commit so the post-commit auto-checkpoint
  # doesn't overwrite our stale marker.
  _stale_stream "$dir" login
  before="$(cat "$dir/.platform/work/login.md")"
  run_cli_capture output "$dir" recover login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Commits to record"
  assert_contains "$output" "work-done"
  assert_contains "$output" "Preview only"
  [[ "$(cat "$dir/.platform/work/login.md")" == "$before" ]] \
    || fail "recover (no --confirm) must not modify the stream file"
}

test_recover_confirm_writes_checkpoint() {
  local dir output
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  (
    cd "$dir"
    printf 'a\n' >> package.json
    git add -A
    git commit -m "recoverable commit" >/dev/null 2>&1
  )
  # Backdate AFTER commit so post-commit auto-checkpoint doesn't reset updated_at.
  _stale_stream "$dir" login
  run_cli_capture output "$dir" recover login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Checkpoint saved"
  assert_file_contains "$dir/.platform/work/login.md" "recoverable commit"
  assert_file_contains "$dir/.platform/work/login.md" "recovered"
}

test_recover_noop_when_no_new_commits() {
  local dir output
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  # Push updated_at into the future so no commits fall in the scan window
  local sf="$dir/.platform/work/login.md"
  local tmp; tmp="$(mktemp)"
  awk '/^updated_at:/ { print "updated_at: 2099-01-01"; next } { print }' "$sf" > "$tmp" && mv "$tmp" "$sf"
  run_cli_capture output "$dir" recover login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Nothing to recover"
}

test_recover_rejects_missing_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  run_cli_capture output "$dir" recover nonexistent
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not found"
}

test_recover_rejects_bad_slug() {
  local dir output
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  run_cli_capture output "$dir" recover "Bad_Slug"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "kebab-case"
}

test_recover_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_recover_fixture "$dir"
  run_cli_capture output "$dir" recover --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard recover"
  assert_contains "$output" "--confirm"
}

test_recover_preview_does_not_write
test_recover_confirm_writes_checkpoint
test_recover_noop_when_no_new_commits
test_recover_rejects_missing_stream
test_recover_rejects_bad_slug
test_recover_help
