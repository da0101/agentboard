#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_entry_fixture() {
  EN_DIR="$(mktemp -d)"
  printf '{}\n' > "$EN_DIR/package.json"
  make_git_repo "$EN_DIR" main
  commit_all "$EN_DIR" initial
  init_project_fixture "$EN_DIR"
}

# An activated entry file: project facts between root-entry markers.
write_activated() {
  cat > "$EN_DIR/$1" <<'EOF2'
<!-- agentboard:root-entry:begin v=1 -->
# Demo

**What this is:** a demo project.

## Stack
Rust + SwiftUI.
<!-- agentboard:root-entry:end v=1 -->

---

## Existing content (user's own)
Keep this line.
EOF2
}

test_kernel_prints_markers_core_and_provider_note() {
  local output
  setup_entry_fixture
  run_cli_capture output "$EN_DIR" entry kernel claude
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "agentboard:kernel:begin"
  assert_contains "$output" "agentboard:kernel:end"
  assert_contains "$output" "ab brief --start"
  assert_contains "$output" "Claude Code:"
  assert_not_contains "$output" "Codex CLI:"
  run_cli_capture output "$EN_DIR" entry kernel codex
  assert_contains "$output" "Codex CLI:"
}

test_kernel_rejects_an_unknown_provider() {
  local output
  setup_entry_fixture
  run_cli_capture output "$EN_DIR" entry kernel emacs
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown provider should fail"
}

test_sync_inserts_the_kernel_before_the_end_marker_and_keeps_everything_else() {
  local output kline eline
  setup_entry_fixture; write_activated CLAUDE.md
  run_cli_capture output "$EN_DIR" entry sync
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "CLAUDE.md: kernel inserted"
  assert_file_contains "$EN_DIR/CLAUDE.md" "Rust + SwiftUI."
  assert_file_contains "$EN_DIR/CLAUDE.md" "Keep this line."
  kline="$(grep -n 'agentboard:kernel:end' "$EN_DIR/CLAUDE.md" | cut -d: -f1)"
  eline="$(grep -n 'agentboard:root-entry:end' "$EN_DIR/CLAUDE.md" | cut -d: -f1)"
  (( kline < eline )) || fail "kernel must sit inside the root-entry block"
}

test_sync_is_idempotent_and_replaces_a_stale_kernel() {
  local output before
  setup_entry_fixture; write_activated CLAUDE.md
  run_cli_capture output "$EN_DIR" entry sync
  before="$(cat "$EN_DIR/CLAUDE.md")"
  run_cli_capture output "$EN_DIR" entry sync
  assert_contains "$output" "kernel replaced"
  assert_eq "$(cat "$EN_DIR/CLAUDE.md")" "$before"
  # make the kernel stale, then sync heals it
  sed -i.bak 's/ab brief --start/STALE-TEXT/' "$EN_DIR/CLAUDE.md" && rm -f "$EN_DIR/CLAUDE.md.bak"
  assert_file_contains "$EN_DIR/CLAUDE.md" "STALE-TEXT"
  run_cli_capture output "$EN_DIR" entry sync
  assert_file_not_contains "$EN_DIR/CLAUDE.md" "STALE-TEXT"
  assert_eq "$(cat "$EN_DIR/CLAUDE.md")" "$before"
}

test_sync_uses_the_right_provider_note_per_file() {
  local output
  setup_entry_fixture; write_activated CLAUDE.md; write_activated AGENTS.md; write_activated GEMINI.md
  run_cli_capture output "$EN_DIR" entry sync
  assert_file_contains "$EN_DIR/CLAUDE.md" "Claude Code:"
  assert_file_contains "$EN_DIR/AGENTS.md" "Codex CLI:"
  assert_file_contains "$EN_DIR/GEMINI.md" "Gemini CLI:"
  assert_file_not_contains "$EN_DIR/AGENTS.md" "Claude Code:"
}

test_sync_leaves_files_without_markers_alone() {
  local output before
  setup_entry_fixture
  printf '# Hand written\nNo markers here.\n' > "$EN_DIR/CLAUDE.md"
  before="$(cat "$EN_DIR/CLAUDE.md")"
  run_cli_capture output "$EN_DIR" entry sync
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no Agentboard markers"
  assert_eq "$(cat "$EN_DIR/CLAUDE.md")" "$before"
}

test_sync_dry_run_writes_nothing() {
  local output before
  setup_entry_fixture; write_activated CLAUDE.md
  before="$(cat "$EN_DIR/CLAUDE.md")"
  run_cli_capture output "$EN_DIR" entry sync --dry-run
  assert_contains "$output" "would insert"
  assert_eq "$(cat "$EN_DIR/CLAUDE.md")" "$before"
}

test_check_passes_for_a_slim_entry_file() {
  local output
  setup_entry_fixture; write_activated CLAUDE.md
  run_cli_capture output "$EN_DIR" entry sync
  run_cli_capture output "$EN_DIR" entry check
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "OK"
  assert_contains "$output" "yes"
}

test_check_fails_when_the_entry_file_blows_the_budget() {
  local output i
  setup_entry_fixture; write_activated CLAUDE.md
  for i in $(seq 1 400); do printf 'Line %s of far too much project detail that should live in a domain card instead.\n' "$i" >> "$EN_DIR/CLAUDE.md"; done
  run_cli_capture output "$EN_DIR" entry check
  [[ "$RUN_STATUS" -ne 0 ]] || fail "check should fail over the budget"
  assert_contains "$output" "FAIL"
}

test_check_warns_between_the_thresholds() {
  local output i
  setup_entry_fixture; write_activated CLAUDE.md
  for i in $(seq 1 130); do printf 'Line %s of project detail that is somewhat long and wordy for a small test.\n' "$i" >> "$EN_DIR/CLAUDE.md"; done
  run_cli_capture output "$EN_DIR" entry check
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "WARN"
}

test_doctor_reports_the_session_start_budget() {
  local output
  setup_entry_fixture; write_activated CLAUDE.md
  run_cli_capture output "$EN_DIR" doctor
  assert_contains "$output" "Session start"
  assert_contains "$output" "tokens"
}

test_doctor_fails_when_the_session_start_budget_is_blown() {
  local output i
  setup_entry_fixture; write_activated CLAUDE.md
  for i in $(seq 1 400); do printf 'Line %s of far too much project detail that should live in a domain card instead.\n' "$i" >> "$EN_DIR/CLAUDE.md"; done
  run_cli_capture output "$EN_DIR" doctor
  [[ "$RUN_STATUS" -ne 0 ]] || fail "doctor should fail over the session-start budget"
  assert_contains "$output" "exceeds 3000"
}

test_kernel_prints_markers_core_and_provider_note
test_kernel_rejects_an_unknown_provider
test_sync_inserts_the_kernel_before_the_end_marker_and_keeps_everything_else
test_sync_is_idempotent_and_replaces_a_stale_kernel
test_sync_uses_the_right_provider_note_per_file
test_sync_leaves_files_without_markers_alone
test_sync_dry_run_writes_nothing
test_check_passes_for_a_slim_entry_file
test_check_fails_when_the_entry_file_blows_the_budget
test_check_warns_between_the_thresholds
test_doctor_reports_the_session_start_budget
test_doctor_fails_when_the_session_start_budget_is_blown
