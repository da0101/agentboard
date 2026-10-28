#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_start_fixture() {
  BS_DIR="$(mktemp -d)"
  printf '{}\n' > "$BS_DIR/package.json"
  make_git_repo "$BS_DIR" main
  commit_all "$BS_DIR" initial
  init_project_fixture "$BS_DIR"
}

add_stream() {
  ( cd "$BS_DIR" && "$TEST_ROOT/bin/ab" new-domain "$2" api >/dev/null 2>&1 || true
    "$TEST_ROOT/bin/ab" new-stream "$1" --domain "$2" --base-branch main --branch "feat/$1" >/dev/null )
}

test_start_with_no_streams_says_so_and_points_at_on_demand_tools() {
  local output
  setup_start_fixture
  run_cli_capture output "$BS_DIR" brief --start
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "none open"
  assert_contains "$output" "ab recall"
  assert_contains "$output" "ab protocol"
}

test_start_lists_open_streams_with_status() {
  local output
  setup_start_fixture
  add_stream login auth; add_stream billing pay
  run_cli_capture output "$BS_DIR" brief --start
  assert_contains "$output" "login ("
  assert_contains "$output" "billing ("
  assert_not_contains "$output" "none open"
}

test_start_hides_closed_streams() {
  local output
  setup_start_fixture
  add_stream login auth
  sed -i.bak 's/^status: .*/status: done/' "$BS_DIR/.platform/work/login.md" && rm -f "$BS_DIR/.platform/work/login.md.bak"
  run_cli_capture output "$BS_DIR" brief --start
  assert_not_contains "$output" "login ("
  assert_contains "$output" "none open"
}

test_start_caps_streams_and_reports_the_rest() {
  local output i
  setup_start_fixture
  for i in 1 2 3 4 5 6 7 8; do add_stream "feat-$i" "dom-$i"; done
  run_cli_capture output "$BS_DIR" brief --start
  assert_contains "$output" "+2 more"
}

test_start_lists_card_names_newest_first_and_caps_them() {
  local output i
  setup_start_fixture
  for i in $(seq 1 35); do
    printf -- '---\nslug: card-%s\nupdated_at: 2026-01-%02d\n---\n# Card %s\n' "$i" "$(( (i % 28) + 1 ))" "$i" > "$BS_DIR/.platform/domains/card-$i.md"
  done
  run_cli_capture output "$BS_DIR" brief --start
  assert_contains "$output" "Cards (35)"
  assert_contains "$output" "+5 (ab recall --list)"
}

test_start_shows_only_never_forget_gotchas_without_the_legend_prefix() {
  local output
  setup_start_fixture
  printf '🔴 never-forget · [api/auth] — tokens expire at midnight UTC\n🟡 usually-matters · [web/form] — minor thing\n' >> "$BS_DIR/.platform/memory/gotchas.md"
  run_cli_capture output "$BS_DIR" brief --start
  assert_contains "$output" "Never forget:"
  assert_contains "$output" "[api/auth] — tokens expire at midnight UTC"
  assert_not_contains "$output" "minor thing"
  assert_not_contains "$output" "never-forget ·"
}

test_start_stays_small() {
  local output
  setup_start_fixture
  add_stream login auth
  run_cli_capture output "$BS_DIR" brief --start
  (( ${#output} < 2400 )) || fail "start packet is ${#output} chars; target is ~2000 (≈500 tokens)"
}

test_start_with_no_streams_says_so_and_points_at_on_demand_tools
test_start_lists_open_streams_with_status
test_start_hides_closed_streams
test_start_caps_streams_and_reports_the_rest
test_start_lists_card_names_newest_first_and_caps_them
test_start_shows_only_never_forget_gotchas_without_the_legend_prefix
test_start_stays_small
