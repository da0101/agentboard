#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_route_fixture() {
  RT_DIR="$(mktemp -d)"
  printf '{}\n' > "$RT_DIR/package.json"
  make_git_repo "$RT_DIR" main
  commit_all "$RT_DIR" initial
  init_project_fixture "$RT_DIR"
}

test_every_tier_in_the_routing_table_has_a_model_row() {
  local tier
  while IFS= read -r tier; do
    awk -F'\t' -v t="$tier" '!/^#/ && $1 == t { f = 1 } END { exit !f }' "$TEST_ROOT/templates/platform/models.tsv" \
      || fail "routing.tsv names tier '$tier' that models.tsv does not define"
  done < <(awk -F'\t' '!/^#/ && NF >= 3 { print $3 }' "$TEST_ROOT/templates/platform/routing.tsv" | sort -u)
}

test_every_route_row_is_well_formed() {
  local bad
  bad="$(awk -F'\t' '!/^#/ && NF > 0 && (NF < 4 || $2 !~ /^(low|medium|high|\*)$/)' "$TEST_ROOT/templates/platform/routing.tsv")"
  [[ -z "$bad" ]] || fail "malformed routing rows: $bad"
}

test_route_recommends_tier_and_claude_model() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route research
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "tier balanced"
  assert_contains "$output" "sonnet"
  assert_contains "$output" "not set"
}

test_route_complexity_changes_the_answer_and_accepts_usage_labels() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route debug low
  assert_contains "$output" "tier balanced"
  run_cli_capture output "$RT_DIR" route debug heavy
  assert_contains "$output" "(high)"
  assert_contains "$output" "tier strong"
  run_cli_capture output "$RT_DIR" route implementation normal
  assert_contains "$output" "(medium)"
}

test_route_wildcard_complexity_applies_to_any_level() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route research high
  assert_contains "$output" "tier balanced"
  run_cli_capture output "$RT_DIR" route chore low
  assert_contains "$output" "tier fast"
}

test_route_for_prints_only_the_model() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route design high --for claude
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "fable"
}

test_route_for_an_unset_provider_prints_nothing_and_fails() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route research --for codex
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unset provider model should exit non-zero"
  assert_eq "$output" ""
}

test_route_unknown_type_lists_the_known_types() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route nonsense
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown type should fail"
  assert_contains "$output" "No route for task type"
  assert_contains "$output" "research"
}

test_route_project_tables_override_the_kit_defaults() {
  local output
  setup_route_fixture
  printf 'balanced\tsonnet\tmy-codex-model\t-\nfrontier\tfable\t-\t-\n' > "$RT_DIR/.platform/models.tsv"
  run_cli_capture output "$RT_DIR" route research --for codex
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "my-codex-model"
  printf 'research\t*\tfrontier\tproject policy\n' > "$RT_DIR/.platform/routing.tsv"
  run_cli_capture output "$RT_DIR" route research --for claude
  assert_eq "$output" "fable"
}

test_route_works_without_a_project_copy_of_the_tables() {
  local output
  setup_route_fixture
  rm -f "$RT_DIR/.platform/routing.tsv" "$RT_DIR/.platform/models.tsv"
  run_cli_capture output "$RT_DIR" route review --for claude
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "sonnet"
}

test_route_without_arguments_prints_the_table_and_types_lists_types() {
  local output
  setup_route_fixture
  run_cli_capture output "$RT_DIR" route
  assert_contains "$output" "implementation"
  assert_contains "$output" "frontier"
  run_cli_capture output "$RT_DIR" route --types
  assert_contains "$output" "debug"
  assert_not_contains "$output" "tier"
}

test_init_ships_the_routing_and_model_tables() {
  setup_route_fixture
  [[ -f "$RT_DIR/.platform/routing.tsv" ]] || fail "init did not install routing.tsv"
  [[ -f "$RT_DIR/.platform/models.tsv" ]] || fail "init did not install models.tsv"
}

test_every_tier_in_the_routing_table_has_a_model_row
test_every_route_row_is_well_formed
test_route_recommends_tier_and_claude_model
test_route_complexity_changes_the_answer_and_accepts_usage_labels
test_route_wildcard_complexity_applies_to_any_level
test_route_for_prints_only_the_model
test_route_for_an_unset_provider_prints_nothing_and_fails
test_route_unknown_type_lists_the_known_types
test_route_project_tables_override_the_kit_defaults
test_route_works_without_a_project_copy_of_the_tables
test_route_without_arguments_prints_the_table_and_types_lists_types
test_init_ships_the_routing_and_model_tables
