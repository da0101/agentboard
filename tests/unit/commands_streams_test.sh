#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_new_domain_new_stream_resolve_and_handoff() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain auth backend --repo frontend >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream auth-fix --domain auth --type bug --agent codex --repo backend --repo frontend >/dev/null
  )

  assert_file_contains "$dir/.platform/domains/auth.md" "repo_ids: [backend, frontend]"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "stream_id: stream-auth-fix"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "repo_ids: [backend, frontend]"
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| auth-fix | bug | planning | codex |"
  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Feature:** auth-fix"

  run_cli_capture output "$dir" resolve auth-fix
  assert_contains "$output" "type: stream"
  assert_contains "$output" "id:   stream-auth-fix"

  run_cli_capture output "$dir" handoff auth-fix
  assert_contains "$output" "Load in this order:"
  assert_contains "$output" ".platform/work/auth-fix.md"
  assert_contains "$output" "Repos in scope:"
}

test_new_stream_rejects_unknown_domain() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth-fix --domain missing-domain
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "./.platform/domains/missing-domain.md does not exist. Create the domain first."
}

test_new_domain_new_stream_resolve_and_handoff
test_new_stream_rejects_unknown_domain
