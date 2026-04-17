#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

test_parse_token_budget_accepts_plain_int() {
  local out
  out="$(parse_token_budget "4000")" || fail "parse_token_budget 4000 failed"
  assert_eq "$out" "4000"
}

test_parse_token_budget_accepts_lowercase_k() {
  local out
  out="$(parse_token_budget "8k")" || fail "parse_token_budget 8k failed"
  assert_eq "$out" "8000"
}

test_parse_token_budget_accepts_uppercase_k() {
  local out
  out="$(parse_token_budget "16K")" || fail "parse_token_budget 16K failed"
  assert_eq "$out" "16000"
}

test_parse_token_budget_rejects_non_numeric() {
  if parse_token_budget "abc" >/dev/null 2>&1; then
    fail "parse_token_budget 'abc' should have failed"
  fi
}

test_parse_token_budget_rejects_unknown_suffix() {
  if parse_token_budget "4m" >/dev/null 2>&1; then
    fail "parse_token_budget '4m' should have failed (only k/K allowed)"
  fi
}

test_estimate_tokens_nonexistent_is_zero() {
  local out
  out="$(estimate_tokens_for_file "/nonexistent/path/xyz.md")"
  assert_eq "$out" "0"
}

test_estimate_tokens_existing_file() {
  local tmp out
  tmp="$(mktemp)"
  # Write exactly 400 bytes → ~100 tokens
  printf '%.0sa' {1..400} > "$tmp"
  out="$(estimate_tokens_for_file "$tmp")"
  rm -f "$tmp"
  assert_eq "$out" "100"
}

setup_handoff_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-domain billing >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --domain billing \
      --base-branch main --branch feat/login >/dev/null
  )
}

test_handoff_without_budget_unchanged() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Load in this order:"
  assert_not_contains "$output" "budget"
  assert_not_contains "$output" "Skipped"
  assert_contains "$output" "domains/auth.md"
  assert_contains "$output" "domains/billing.md"
}

test_handoff_generous_budget_includes_all_with_annotation() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login --budget 10k
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "budget 10k tokens"
  assert_contains "$output" "domains/auth.md"
  assert_contains "$output" "domains/billing.md"
  assert_not_contains "$output" "Skipped (budget tight)"
}

test_handoff_tight_budget_drops_secondary_domain() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login --budget 500
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "budget 500 tokens"
  assert_contains "$output" "Skipped (budget tight)"
  assert_contains "$output" "domains/billing.md"
  # primary domain still loaded
  assert_contains "$output" ".platform/domains/auth.md"
}

test_handoff_primary_domain_always_included_even_under_budget() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  # Budget too small even for the minimum pack; primary must still be loaded
  run_cli_capture output "$dir" handoff login --budget 1
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" ".platform/work/BRIEF.md"
  assert_contains "$output" ".platform/work/login.md"
  assert_contains "$output" ".platform/domains/auth.md"
}

test_handoff_rejects_invalid_budget_value() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login --budget bogus
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Invalid --budget"
}

test_handoff_rejects_missing_budget_value() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff login --budget
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "handoff requires a value after --budget"
}

test_handoff_help_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_handoff_fixture "$dir"

  run_cli_capture output "$dir" handoff --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard handoff"
  assert_contains "$output" "--budget"
}

test_parse_token_budget_accepts_plain_int
test_parse_token_budget_accepts_lowercase_k
test_parse_token_budget_accepts_uppercase_k
test_parse_token_budget_rejects_non_numeric
test_parse_token_budget_rejects_unknown_suffix
test_estimate_tokens_nonexistent_is_zero
test_estimate_tokens_existing_file
test_handoff_without_budget_unchanged
test_handoff_generous_budget_includes_all_with_annotation
test_handoff_tight_budget_drops_secondary_domain
test_handoff_primary_domain_always_included_even_under_budget
test_handoff_rejects_invalid_budget_value
test_handoff_rejects_missing_budget_value
test_handoff_help_flag
