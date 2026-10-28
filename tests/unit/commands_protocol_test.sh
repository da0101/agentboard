#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_protocol_fixture() {
  PR_DIR="$(mktemp -d)"
  printf '{}\n' > "$PR_DIR/package.json"
  make_git_repo "$PR_DIR" main
  commit_all "$PR_DIR" initial
  init_project_fixture "$PR_DIR"
}

test_init_installs_the_protocol_files() {
  setup_protocol_fixture
  local n
  n="$(ls "$PR_DIR"/.platform/protocols/*.md | wc -l | tr -d ' ')"
  (( n >= 8 )) || fail "expected at least 8 protocol files, found $n"
}

test_protocol_lists_every_protocol_with_its_trigger() {
  local output name
  setup_protocol_fixture
  run_cli_capture output "$PR_DIR" protocol
  assert_status "$RUN_STATUS" 0
  for name in new-task closure handoff qa roles audit reasoning subagents; do
    assert_contains "$output" "$name"
  done
  assert_contains "$output" "not already tracked"
}

test_protocol_prints_one_protocol() {
  local output
  setup_protocol_fixture
  run_cli_capture output "$PR_DIR" protocol new-task
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "# Protocol: New task bootstrap"
  assert_contains "$output" "Check \`ACTIVE.md\`"
  assert_not_contains "$output" "Protocol: Stream closure"
}

test_closure_protocol_documents_the_knowledge_delta() {
  local output
  setup_protocol_fixture
  run_cli_capture output "$PR_DIR" protocol closure
  assert_contains "$output" "## Knowledge delta"
  assert_contains "$output" "closure_approved: true"
  assert_contains "$output" "ab close <stream-slug> --confirm"
}

test_protocol_rejects_unknown_and_malformed_names() {
  local output
  setup_protocol_fixture
  run_cli_capture output "$PR_DIR" protocol nope
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown protocol should fail"
  assert_contains "$output" "Unknown protocol"
  run_cli_capture output "$PR_DIR" protocol "../../etc/passwd"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "path-like name should fail"
}

test_update_restores_a_missing_protocol() {
  local output
  setup_protocol_fixture
  rm "$PR_DIR/.platform/protocols/qa.md"
  run_cli_capture output "$PR_DIR" update
  assert_status "$RUN_STATUS" 0
  [[ -f "$PR_DIR/.platform/protocols/qa.md" ]] || fail "ab update did not restore protocols/qa.md"
}

test_protocol_without_a_project_fails() {
  local output dir
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" protocol
  [[ "$RUN_STATUS" -ne 0 ]] || fail "protocol outside a project should fail"
}

test_init_installs_the_protocol_files
test_protocol_lists_every_protocol_with_its_trigger
test_protocol_prints_one_protocol
test_closure_protocol_documents_the_knowledge_delta
test_protocol_rejects_unknown_and_malformed_names
test_update_restores_a_missing_protocol
test_protocol_without_a_project_fails
