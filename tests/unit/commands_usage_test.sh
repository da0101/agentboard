#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

# All usage tests use an isolated HOME so they never touch ~/.ab/usage.db

seed_legacy_usage_db() {
  local home_dir="$1"
  mkdir -p "$home_dir/.ab"
  sqlite3 "$home_dir/.ab/usage.db" "
    CREATE TABLE usage (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
      agent_provider TEXT NOT NULL,
      model TEXT,
      stream_slug TEXT,
      repo TEXT,
      task_type TEXT,
      input_tokens INTEGER,
      output_tokens INTEGER,
      total_tokens INTEGER,
      estimated_cost REAL,
      session_id TEXT
    );
    INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens, estimated_cost, session_id)
    VALUES ('claude', 'claude-opus-4-7', 'legacy-stream', 'legacy-repo', 'normal', 1000, 500, 1500, 0, 'legacy');
  "
}

# ── log ────────────────────────────────────────────────────────────────────────

test_usage_log_creates_entry() {
  local dir output
  dir="$(mktemp -d)"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
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

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --input 100 --output 50

  assert_status "$RUN_STATUS" 1
}

test_usage_log_totals_input_plus_output() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --model codex-4-5 --input 3000 --output 1000 >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage history
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "4000"
}

# ── summary ────────────────────────────────────────────────────────────────────

test_usage_summary_exits_zero_on_empty_db() {
  local dir output
  dir="$(mktemp -d)"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage summary
  assert_status "$RUN_STATUS" 0
}

test_usage_summary_shows_logged_data() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider gemini --model gemini-2.0-flash --input 5000 --output 2000 \
    --repo my-project --type review >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage summary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "gemini"
  assert_contains "$output" "7000"
}

test_usage_summary_shows_complexity_breakdown() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider gemini --model gemini-2.0-flash --input 5000 --output 2000 \
    --repo my-project --type review --complexity heavy >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage summary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "By Complexity"
  assert_contains "$output" "heavy"
}

# ── stream subcommand ──────────────────────────────────────────────────────────

test_usage_stream_shows_stream_breakdown() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-sonnet-4-6 \
    --stream my-feature --input 2000 --output 500 --complexity normal >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --model codex-4-5 \
    --stream my-feature --input 1000 --output 300 --complexity heavy >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage stream my-feature
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "my-feature"
  assert_contains "$output" "claude"
  assert_contains "$output" "codex"
  assert_contains "$output" "Complexity"
  assert_contains "$output" "heavy"
}

test_usage_stream_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage stream
  assert_status "$RUN_STATUS" 1
}

# ── dashboard ──────────────────────────────────────────────────────────────────

test_usage_dashboard_exits_zero_on_empty_db() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage dashboard
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "AGENTBOARD TOKEN DASHBOARD"
}

test_usage_dashboard_week_flag() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage dashboard --week
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Last 7 Days"
}

test_usage_dashboard_today_flag() {
  local dir output
  dir="$(mktemp -d)"
  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage dashboard --today
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Today"
}

test_usage_dashboard_shows_task_breakdown() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-6 --input 50000 --output 10000 \
    --type implementation --repo proj >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-6 --input 5000 --output 1000 \
    --type research --repo proj >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage dashboard --week
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
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-6 --input 1000 --output 200 >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage learn
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Not enough data"
}

test_usage_read_commands_handle_legacy_schema() {
  local dir output
  dir="$(mktemp -d)"
  seed_legacy_usage_db "$dir"
  chmod 555 "$dir/.ab"
  chmod 444 "$dir/.ab/usage.db"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage summary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "legacy-repo"
  assert_contains "$output" "By Complexity"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage history
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "legacy-stream"

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage stream legacy-stream
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "legacy-stream"
}

test_usage_learn_flags_generic_labels_and_coarse_logging() {
  local dir output
  dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-7 --stream watch-install \
    --input 200000 --output 38000 --type normal >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-7 --stream watch-install \
    --input 50000 --output 4000 --type heavy >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --model gpt-5.4 --stream other-stream \
    --input 1000 --output 500 --type debug >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --model gpt-5.4 --stream other-stream \
    --input 900 --output 400 --type audit >/dev/null
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --model gpt-5.4 --stream other-stream \
    --input 800 --output 300 --type research >/dev/null

  run_and_capture output env HOME="$dir" "$TEST_ROOT/bin/ab" usage learn
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "GENERIC_TASK_LABELS"
  assert_contains "$output" "COARSE_LOGGING"
  assert_contains "$output" "watch-install"
}

# ── run all ────────────────────────────────────────────────────────────────────

test_usage_log_creates_entry
test_usage_log_requires_provider
test_usage_log_totals_input_plus_output
test_usage_summary_exits_zero_on_empty_db
test_usage_summary_shows_logged_data
test_usage_summary_shows_complexity_breakdown
test_usage_stream_shows_stream_breakdown
test_usage_stream_requires_slug
test_usage_dashboard_exits_zero_on_empty_db
test_usage_dashboard_week_flag
test_usage_dashboard_today_flag
test_usage_dashboard_shows_task_breakdown
test_usage_learn_requires_min_data
test_usage_read_commands_handle_legacy_schema
test_usage_learn_flags_generic_labels_and_coarse_logging
