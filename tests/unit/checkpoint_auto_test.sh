#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_auto_fixture() {
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

test_auto_mode_writes_checkpoint_from_commit_message() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"

  (
    cd "$dir"
    printf 'change\n' >> package.json
    git add -A
    git commit -m "feat: add login form" >/dev/null 2>&1
  )

  run_cli_capture output "$dir" checkpoint --auto
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/work/login.md" "feat: add login form"
  assert_file_contains "$dir/.platform/work/login.md" "(auto)"
  assert_file_contains "$dir/.platform/work/login.md" "auto-saved from commit"
}

test_auto_mode_is_idempotent_for_same_commit() {
  local dir output count_first count_second
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"

  (
    cd "$dir"
    printf 'change\n' >> package.json
    git add -A
    git commit -m "one commit" >/dev/null 2>&1
  )

  run_cli_capture output "$dir" checkpoint --auto
  count_first="$(grep -c "(auto)" "$dir/.platform/work/login.md" || true)"
  run_cli_capture output "$dir" checkpoint --auto
  count_second="$(grep -c "(auto)" "$dir/.platform/work/login.md" || true)"
  assert_eq "$count_first" "$count_second"
}

test_auto_mode_silent_when_multiple_active_streams() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"

  (
    cd "$dir"
    git checkout -q main
    "$TEST_ROOT/bin/agentboard" new-stream payments \
      --domain auth --base-branch main --branch feat/payments >/dev/null
    git add .platform
    git commit -m "second stream" >/dev/null 2>&1
  )

  run_cli_capture output "$dir" checkpoint --auto
  assert_status "$RUN_STATUS" 0
  # With ambiguity, auto mode must not touch any stream file
  assert_file_not_contains "$dir/.platform/work/login.md" "second stream"
  assert_file_not_contains "$dir/.platform/work/payments.md" "second stream"
}

test_auto_mode_accepts_explicit_slug() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"

  (
    cd "$dir"
    git checkout -q main
    "$TEST_ROOT/bin/agentboard" new-stream payments \
      --domain auth --base-branch main --branch feat/payments >/dev/null
    git add .platform
    git commit -m "picked target commit" >/dev/null 2>&1
  )

  # Disambiguate by passing slug explicitly
  run_cli_capture output "$dir" checkpoint --auto payments
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/work/payments.md" "picked target commit"
  assert_file_not_contains "$dir/.platform/work/login.md" "picked target commit"
}

test_post_commit_hook_template_calls_auto() {
  local hook="$TEST_ROOT/templates/platform/scripts/hooks/post-commit"
  [[ -f "$hook" ]] || fail "post-commit template missing"
  grep -q "agentboard checkpoint --auto" "$hook" \
    || fail "post-commit template does not call 'agentboard checkpoint --auto'"
}

test_auto_mode_writes_checkpoint_from_commit_message
test_auto_mode_is_idempotent_for_same_commit
test_auto_mode_silent_when_multiple_active_streams
test_auto_mode_accepts_explicit_slug
test_post_commit_hook_template_calls_auto
