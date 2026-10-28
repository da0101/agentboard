#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A project polluted in every way tidy knows about, plus things it must NOT touch.
setup_tidy_fixture() {
  TD_DIR="$(mktemp -d)"
  printf '{}\n' > "$TD_DIR/package.json"
  make_git_repo "$TD_DIR" main
  commit_all "$TD_DIR" initial
  init_project_fixture "$TD_DIR"
  local p="$TD_DIR/.platform"
  mkdir -p "$p/work/archive/qa" "$p/graphify" "$p/work/qa/evidence/old-stream" "$p/work/qa/evidence/live-stream"
  printf 'old stream\n' > "$p/work/archive/old-stream.md"
  printf 'old qa\n' > "$p/work/archive/qa/old-stream-manual-qa.md"
  printf '{"nodes":[]}\n' > "$p/graphify/graph.json"
  printf 'dump\n' > "$p/memory/session-2026-10-01.md"
  printf '{}\n' > "$p/events-2026-09-01.jsonl"
  # QA: one orphan (stream gone), one belonging to a live stream
  printf 'orphan qa\n' > "$p/work/qa/old-stream-manual-qa.md"
  printf 'orphan evidence\n' > "$p/work/qa/evidence/old-stream/shot.png"
  printf 'live qa\n' > "$p/work/qa/live-stream-manual-qa.md"
  printf 'live evidence\n' > "$p/work/qa/evidence/live-stream/shot.png"
  # an open, long-untouched stream
  ( cd "$TD_DIR" && "$TEST_ROOT/bin/ab" new-domain auth api >/dev/null \
    && "$TEST_ROOT/bin/ab" new-stream live-stream --domain auth --base-branch main --branch feat/x >/dev/null )
  sed -i.bak 's/^updated_at: .*/updated_at: 2020-01-01/' "$p/work/live-stream.md" && rm -f "$p/work/live-stream.md.bak"
  # a closed row left in the registry
  printf '| shipped | feature | closed | claude | 2026-10-01 |\n' > "$TD_DIR/row.tmp"
  awk -v row="$(cat "$TD_DIR/row.tmp")" '{ print } /^\| Stream \| Type/ { getline; print; print row }' "$p/work/ACTIVE.md" > "$TD_DIR/a.tmp" && mv "$TD_DIR/a.tmp" "$p/work/ACTIVE.md"; rm -f "$TD_DIR/row.tmp"
  # an installed extra skill
  ( cd "$TD_DIR" && "$TEST_ROOT/bin/ab" skill install ab-canary >/dev/null )
  # content that must survive
  printf '# Memory\nkeep\n' > "$p/memory/gotchas-keep.md"
}

tree_sig() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum 2>/dev/null | shasum ); }

test_report_mode_changes_nothing_and_names_every_finding() {
  local output before
  setup_tidy_fixture
  before="$(tree_sig "$TD_DIR")"
  run_cli_capture output "$TD_DIR" tidy
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "report only"
  assert_contains "$output" "work/archive/"
  assert_contains "$output" "graphify/"
  assert_contains "$output" "memory/session-*.md"
  assert_contains "$output" "rotated event logs"
  assert_contains "$output" "QA files of closed streams"
  assert_contains "$output" "ACTIVE.md closed rows"
  assert_contains "$output" "extra skills installed"
  assert_contains "$output" "stale streams"
  assert_contains "$output" "live-stream"
  assert_eq "$(tree_sig "$TD_DIR")" "$before"
}

test_apply_moves_pollution_to_cold_store_and_removes_it_from_the_repo() {
  local output cold p="$TD_DIR"
  setup_tidy_fixture; p="$TD_DIR/.platform"
  run_cli_capture output "$TD_DIR" tidy --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -e "$p/work/archive" ]] || fail "archive should be gone"
  [[ ! -e "$p/graphify" ]] || fail "graphify should be gone"
  [[ ! -e "$p/memory/session-2026-10-01.md" ]] || fail "session dump should be gone"
  [[ ! -e "$p/events-2026-09-01.jsonl" ]] || fail "rotated log should be gone"
  [[ ! -e "$p/work/qa/old-stream-manual-qa.md" && ! -e "$p/work/qa/evidence/old-stream" ]] || fail "orphan QA should be gone"
  cold="$(ls -d "$AGENTBOARD_COLD_DIR"/*/tidy-* | tail -1)"
  [[ -f "$cold/.platform/work/archive/old-stream.md" ]] || fail "archive not copied to cold store"
  [[ -f "$cold/.platform/graphify/graph.json" ]] || fail "graph not copied to cold store"
  [[ -f "$cold/.platform/work/qa/old-stream-manual-qa.md" ]] || fail "orphan QA not copied to cold store"
  assert_eq "$(cat "$cold/.platform/work/archive/old-stream.md")" "old stream"
}

test_apply_never_touches_live_streams_domains_memory_or_live_qa() {
  local output p
  setup_tidy_fixture; p="$TD_DIR/.platform"
  run_cli_capture output "$TD_DIR" tidy --apply
  [[ -f "$p/work/live-stream.md" ]] || fail "open stream was touched"
  [[ -f "$p/domains/auth.md" ]] || fail "domain card was touched"
  [[ -f "$p/memory/gotchas-keep.md" ]] || fail "memory was touched"
  [[ -f "$p/work/qa/live-stream-manual-qa.md" ]] || fail "live stream's QA was removed"
  [[ -f "$p/work/qa/evidence/live-stream/shot.png" ]] || fail "live stream's evidence was removed"
}

test_apply_drops_closed_rows_prunes_extras_and_keeps_open_rows() {
  local output p
  setup_tidy_fixture; p="$TD_DIR/.platform"
  run_cli_capture output "$TD_DIR" tidy --apply
  assert_file_not_contains "$p/work/ACTIVE.md" "| shipped |"
  assert_file_contains "$p/work/ACTIVE.md" "live-stream"
  [[ ! -d "$TD_DIR/.claude/skills/ab-canary" ]] || fail "extra skill should be pruned"
  [[ -d "$TD_DIR/.claude/skills/ab-workflow" ]] || fail "core skill must stay"
}

test_apply_syncs_the_kernel_only_into_marker_managed_entry_files() {
  local output
  setup_tidy_fixture
  printf '<!-- agentboard:root-entry:begin v=1 -->\n# Demo\n<!-- agentboard:root-entry:end v=1 -->\n' > "$TD_DIR/AGENTS.md"
  printf '# hand written, no markers\n' > "$TD_DIR/GEMINI.md"
  run_cli_capture output "$TD_DIR" tidy --apply
  assert_file_contains "$TD_DIR/AGENTS.md" "agentboard:kernel:begin"
  assert_file_not_contains "$TD_DIR/GEMINI.md" "agentboard:kernel"
  assert_contains "$output" "no Agentboard markers"
}

test_apply_is_idempotent() {
  local output
  setup_tidy_fixture
  run_cli_capture output "$TD_DIR" tidy --apply
  run_cli_capture output "$TD_DIR" tidy --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Nothing to tidy"
}

test_stale_streams_are_reported_never_changed() {
  local output before
  setup_tidy_fixture
  before="$(cat "$TD_DIR/.platform/work/live-stream.md")"
  run_cli_capture output "$TD_DIR" tidy --apply --days 30
  assert_contains "$output" "live-stream"
  assert_eq "$(cat "$TD_DIR/.platform/work/live-stream.md")" "$before"
  run_cli_capture output "$TD_DIR" tidy --days 999999
  assert_not_contains "$output" "stale streams"
}

test_tidy_on_a_clean_project_has_nothing_to_do() {
  local output dir
  dir="$(mktemp -d)"; printf '{}\n' > "$dir/package.json"; make_git_repo "$dir" main; commit_all "$dir" initial
  init_project_fixture "$dir"
  run_cli_capture output "$dir" tidy
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Nothing to tidy"
}

test_tidy_fails_outside_a_project_and_rejects_bad_flags() {
  local output dir
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" tidy
  [[ "$RUN_STATUS" -ne 0 ]] || fail "tidy outside a project should fail"
  setup_tidy_fixture
  run_cli_capture output "$TD_DIR" tidy --bogus
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown flag should fail"
}

test_report_mode_changes_nothing_and_names_every_finding
test_apply_moves_pollution_to_cold_store_and_removes_it_from_the_repo
test_apply_never_touches_live_streams_domains_memory_or_live_qa
test_apply_drops_closed_rows_prunes_extras_and_keeps_open_rows
test_apply_syncs_the_kernel_only_into_marker_managed_entry_files
test_apply_is_idempotent
test_stale_streams_are_reported_never_changed
test_tidy_on_a_clean_project_has_nothing_to_do
test_tidy_fails_outside_a_project_and_rejects_bad_flags
