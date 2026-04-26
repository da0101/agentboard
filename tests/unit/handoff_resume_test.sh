#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_handoff_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth \
      --base-branch main --branch feat/login >/dev/null
  )
}

test_handoff_includes_footer_for_next_agent() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "For the agent reading this"
  assert_contains "$output" "ab checkpoint login"
}

test_handoff_shows_resume_state_after_checkpoint() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" checkpoint login \
      --what "added webhook handler in src/api/webhook.ts" \
      --next "write the integration test for the happy path" \
      --focus "src/api/webhook.ts:88" >/dev/null
  )

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Resume state"
  assert_contains "$output" "added webhook handler"
  assert_contains "$output" "integration test for the happy path"
  assert_contains "$output" "src/api/webhook.ts:88"
}

test_handoff_warns_when_stream_is_stale() {
  local dir output stream_file yesterday
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  # Manually age the updated_at date by one day to simulate staleness
  case "$(uname)" in
    Darwin) yesterday="$(date -v -1d +%F)" ;;
    *)      yesterday="$(date -d 'yesterday' +%F)" ;;
  esac
  sed -i.bak "s/^updated_at: .*/updated_at: $yesterday/" "$stream_file"
  rm -f "$stream_file.bak"

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Stream state last updated"
  assert_contains "$output" "run"
  assert_contains "$output" "checkpoint"
}

test_handoff_no_staleness_warning_when_current() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  assert_not_contains "$output" "Stream state last updated"
}

test_handoff_resume_state_overrides_brief_excerpts() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" checkpoint login \
      --what "did thing" --next "do next thing" >/dev/null
  )

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  # When Resume state has real content, the old "What we are building" /
  # "Current state" sections from BRIEF should not also be printed.
  assert_not_contains "$output" "What we are building:"
  assert_not_contains "$output" "Current state:"
}

test_handoff_includes_footer_for_next_agent
test_handoff_shows_resume_state_after_checkpoint
test_handoff_warns_when_stream_is_stale
test_handoff_no_staleness_warning_when_current
test_handoff_resume_state_overrides_brief_excerpts
