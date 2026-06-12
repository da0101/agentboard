#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

ALL_ROLE_SLUGS="backend-architect code-auditor data-analyst debugger devops-engineer feature-builder frontend-engineer pair-programmer perf-engineer product-manager qa-engineer refactor-architect security-engineer startup-mvp tech-advisor tech-writer"

# ---------------------------------------------------------------------------
# ab role list
# ---------------------------------------------------------------------------

test_role_list_shows_all_shipped_roles() {
  local dir output slug
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role list
  assert_status "$RUN_STATUS" 0
  for slug in $ALL_ROLE_SLUGS; do
    assert_contains "$output" "[role:$slug]"
  done
  # INDEX.md is routing metadata, never a listable role
  assert_not_contains "$output" "[role:INDEX]"
}

test_role_defaults_to_list_subcommand() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "[role:pair-programmer]"
}

test_role_list_without_pack_prints_update_hint_and_exits_zero() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -rf "$dir/.platform/roles"

  run_cli_capture output "$dir" role list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No role pack found"
  assert_contains "$output" "ab update"
}

test_role_list_with_empty_pack_dir_prints_update_hint_and_exits_zero() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -f "$dir/.platform/roles/"*.md

  run_cli_capture output "$dir" role list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No role files in .platform/roles/"
  assert_contains "$output" "ab update"
}

# ---------------------------------------------------------------------------
# ab role show
# ---------------------------------------------------------------------------

test_role_show_prints_role_file_in_full() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role show pair-programmer
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "slug: pair-programmer"
  assert_contains "$output" "# Role: Pair Programmer (default)"
  assert_contains "$output" "## Constraints"
}

test_role_show_unknown_slug_fails_and_lists_available() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role show nonexistent
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown role: 'nonexistent'"
  assert_contains "$output" "Available roles:"
  assert_contains "$output" "pair-programmer"
  assert_contains "$output" "debugger"
}

test_role_show_rejects_index_as_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role show INDEX
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown role: 'INDEX'"
}

test_role_show_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" role show
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Usage: ab role show <slug>"
}

test_role_show_without_pack_fails_with_update_hint() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -rf "$dir/.platform/roles"

  run_cli_capture output "$dir" role show pair-programmer
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No role pack found"
  assert_contains "$output" "ab update"
}

# ---------------------------------------------------------------------------
# ab role --help / unknown subcommand
# ---------------------------------------------------------------------------

test_role_help_exits_zero_and_mentions_list_and_show() {
  local dir output
  dir="$(mktemp -d)"

  run_cli_capture output "$dir" role --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab role [list]"
  assert_contains "$output" "ab role show <slug>"
}

test_role_rejects_unknown_subcommand() {
  local dir output
  dir="$(mktemp -d)"

  run_cli_capture output "$dir" role bogus
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown role subcommand: bogus"
}

# ---------------------------------------------------------------------------
# ab update restores the role pack
# ---------------------------------------------------------------------------

test_update_restores_deleted_role_pack() {
  local dir output fname count
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -rf "$dir/.platform/roles"

  run_cli_capture output "$dir" update
  assert_status "$RUN_STATUS" 0

  for fname in INDEX.md backend-architect.md code-auditor.md data-analyst.md \
    debugger.md devops-engineer.md feature-builder.md frontend-engineer.md \
    pair-programmer.md perf-engineer.md product-manager.md qa-engineer.md \
    refactor-architect.md security-engineer.md startup-mvp.md \
    tech-advisor.md tech-writer.md; do
    [[ -f "$dir/.platform/roles/$fname" ]] || fail "update did not restore roles/$fname"
  done
  count="$(ls "$dir/.platform/roles" | wc -l | tr -d ' ')"
  assert_eq "$count" "17"

  run_cli_capture output "$dir" role list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "[role:pair-programmer]"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------

test_role_list_shows_all_shipped_roles
test_role_defaults_to_list_subcommand
test_role_list_without_pack_prints_update_hint_and_exits_zero
test_role_list_with_empty_pack_dir_prints_update_hint_and_exits_zero
test_role_show_prints_role_file_in_full
test_role_show_unknown_slug_fails_and_lists_available
test_role_show_rejects_index_as_slug
test_role_show_requires_slug
test_role_show_without_pack_fails_with_update_hint
test_role_help_exits_zero_and_mentions_list_and_show
test_role_rejects_unknown_subcommand
test_update_restores_deleted_role_pack
