#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# ab rescan — basic invocation
# ---------------------------------------------------------------------------

test_rescan_exits_zero_when_platform_and_protocol_present() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "RESCAN.md"
}

test_rescan_mentions_last_scan_when_log_has_activation_entry() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '2026-01-15 — ab activation — initial scan\n' \
    >> "$dir/.platform/memory/log.md"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab activation"
}

test_rescan_shows_never_when_log_has_no_scan_entry() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  # truncate log so it has no scan/activation line
  printf '# Activity log\n' > "$dir/.platform/memory/log.md"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "never"
}

test_rescan_warns_and_exits_1_when_no_rescan_protocol() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -f "$dir/.platform/RESCAN.md"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "ab update"
}

test_rescan_fails_when_no_platform_dir() {
  local dir output
  dir="$(mktemp -d)"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No .platform/"
}

test_rescan_shows_domain_and_convention_counts() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '# domain\n' > "$dir/.platform/domains/auth.md"
  mkdir -p "$dir/.platform/conventions"
  printf '# conv\n'   > "$dir/.platform/conventions/api.md"

  run_cli_capture output "$dir" rescan
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "domains/"
  assert_contains "$output" "conventions/"
}

# ---------------------------------------------------------------------------
# RESCAN.md template contract
# ---------------------------------------------------------------------------

RESCAN_TEMPLATE="$TEST_ROOT/templates/platform/RESCAN.md"

test_rescan_template_exists() {
  [[ -f "$RESCAN_TEMPLATE" ]] || fail "templates/platform/RESCAN.md missing"
}

test_rescan_template_has_required_sections() {
  local section
  for section in \
    "## Step 1" \
    "## Step 2" \
    "## Step 3" \
    "## Step 4" \
    "Protected files"
  do
    grep -q "$section" "$RESCAN_TEMPLATE" \
      || fail "RESCAN.md missing section: $section"
  done
}

test_rescan_template_lists_protected_files() {
  local protected
  for protected in \
    "decisions.md" \
    "ACTIVE.md" \
    "BRIEF.md" \
    "learnings.md" \
    "gotchas.md"
  do
    grep -q "$protected" "$RESCAN_TEMPLATE" \
      || fail "RESCAN.md does not mention protected file: $protected"
  done
}

test_rescan_template_is_stack_agnostic() {
  local hits
  hits="$(grep -En 'React|Django|Next\.js|Vue|Flutter|Rails|Express' "$RESCAN_TEMPLATE" || true)"
  [[ -z "$hits" ]] || fail "RESCAN.md must be stack-agnostic, found: $hits"
}

# ---------------------------------------------------------------------------
# Entry templates reference rescan trigger
# ---------------------------------------------------------------------------

test_all_entry_templates_reference_rescan_trigger() {
  local t
  for t in \
    "$TEST_ROOT/templates/root/CLAUDE.md.template" \
    "$TEST_ROOT/templates/root/CLAUDE.md.hub.template" \
    "$TEST_ROOT/templates/root/AGENTS.md.template" \
    "$TEST_ROOT/templates/root/GEMINI.md.template"
  do
    [[ -f "$t" ]] || fail "$t missing"
    assert_file_contains "$t" "RESCAN.md"
    assert_file_contains "$t" "update the platform"
  done
}

# ---------------------------------------------------------------------------
# ab update installs RESCAN.md
# ---------------------------------------------------------------------------

test_update_installs_rescan_md() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -f "$dir/.platform/RESCAN.md"

  run_cli_capture output "$dir" update
  assert_status "$RUN_STATUS" 0
  [[ -f "$dir/.platform/RESCAN.md" ]] || fail "ab update did not install RESCAN.md"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------

test_rescan_exits_zero_when_platform_and_protocol_present
test_rescan_mentions_last_scan_when_log_has_activation_entry
test_rescan_shows_never_when_log_has_no_scan_entry
test_rescan_warns_and_exits_1_when_no_rescan_protocol
test_rescan_fails_when_no_platform_dir
test_rescan_shows_domain_and_convention_counts
test_rescan_template_exists
test_rescan_template_has_required_sections
test_rescan_template_lists_protected_files
test_rescan_template_is_stack_agnostic
test_all_entry_templates_reference_rescan_trigger
test_update_installs_rescan_md
