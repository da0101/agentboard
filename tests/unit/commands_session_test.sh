#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_claim_release_log_and_status() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  AGENTBOARD_AGENT="codex-agent" run_cli_capture output "$dir" claim "Investigate auth regression"
  assert_contains "$output" "Claimed: Investigate auth regression"
  assert_file_contains "$dir/.platform/sessions/ACTIVE.md" "codex-agent"

  AGENTBOARD_AGENT="codex-agent" run_cli_capture output "$dir" release
  assert_contains "$output" "Released all claims for codex-agent"
  assert_file_not_contains "$dir/.platform/sessions/ACTIVE.md" "codex-agent"

  run_cli_capture output "$dir" log "Added a test entry"
  assert_contains "$output" "Logged: Added a test entry"
  assert_file_contains "$dir/.platform/log.md" "Added a test entry"

  run_cli_capture output "$dir" status
  assert_contains "$output" "Current Status"
}

test_claim_release_log_and_status
