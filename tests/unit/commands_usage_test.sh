#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

# All usage tests use an isolated HOME so they never touch ~/.agentboard/usage.db

# ── log ────────────────────────────────────────────────────────────────────────

test_usage_log_creates_entry() {
  local dir output
  dir="$(mktemp -d)"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --model claude-sonnet-4-6 \
    --input 1200 --output 400 \
    --stream test-stream --repo test-repo --type research \
    --note "unit test entry"

  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "1600"
  assert_contains "$output" "claude"
}

test_usage_log_requires_provider() {
  local dir output
  dir="$(mktemp -d)"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --input 100 --output 50

  assert_status "$RUN_STATUS" 1
}

test_usage_log_totals_input_plus_output() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider codex --model codex-4-5 --input 3000 --output 1000 >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage history
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "4000"
}

# ── summary ────────────────────────────────────────────────────────────────────

test_usage_summary_exits_zero_on_empty_db() {
  local dir output
  dir="$(mktemp -d)"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage summary
  assert_status "$RUN_STATUS" 0
}

test_usage_summary_shows_logged_data() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider gemini --model gemini-2.0-flash --input 5000 --output 2000 \
    --repo my-project --type review >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage summary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "gemini"
  assert_contains "$output" "7000"
}

# ── stream subcommand ──────────────────────────────────────────────────────────

test_usage_stream_shows_stream_breakdown() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --model claude-sonnet-4-6 \
    --stream my-feature --input 2000 --output 500 >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider codex --model codex-4-5 \
    --stream my-feature --input 1000 --output 300 >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage stream my-feature
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "my-feature"
  assert_contains "$output" "claude"
  assert_contains "$output" "codex"
}

test_usage_stream_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage stream
  assert_status "$RUN_STATUS" 1
}

# ── dashboard ──────────────────────────────────────────────────────────────────

test_usage_dashboard_exits_zero_on_empty_db() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage dashboard
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "AGENTBOARD TOKEN DASHBOARD"
}

test_usage_dashboard_week_flag() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage dashboard --week
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Last 7 Days"
}

test_usage_dashboard_today_flag() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage dashboard --today
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Today"
}

test_usage_dashboard_shows_task_breakdown() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --model claude-opus-4-6 --input 50000 --output 10000 \
    --type implementation --repo proj >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --model claude-opus-4-6 --input 5000 --output 1000 \
    --type research --repo proj >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage dashboard --week
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "WHO DID THE WORK"
  assert_contains "$output" "implementation"
  assert_contains "$output" "research"
  assert_contains "$output" "claude"
}

# ── learn ──────────────────────────────────────────────────────────────────────

test_usage_learn_requires_min_data() {
  local dir output
  dir="$(mktemp -d)"
  # only 1 entry — below the 5-segment threshold
  env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --model claude-opus-4-6 --input 1000 --output 200 >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/agentboard" usage learn
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Not enough data"
}

# ── run all ────────────────────────────────────────────────────────────────────

test_usage_log_creates_entry
test_usage_log_requires_provider
test_usage_log_totals_input_plus_output
test_usage_summary_exits_zero_on_empty_db
test_usage_summary_shows_logged_data
test_usage_stream_shows_stream_breakdown
test_usage_stream_requires_slug
test_usage_dashboard_exits_zero_on_empty_db
test_usage_dashboard_week_flag
test_usage_dashboard_today_flag
test_usage_dashboard_shows_task_breakdown
test_usage_learn_requires_min_data
