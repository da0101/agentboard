#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# Cumulative-mode usage logging. LLMs report running session totals
# (Claude Code shows the context bar in cumulative terms), so the CLI
# must compute deltas automatically instead of double-counting.

_skip_unless_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed" >&2
    return 1
  }
}

_usage_row_count() {
  local db="$1" stream="$2"
  sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE stream_slug = '$stream';"
}

_usage_sum_input() {
  local db="$1" stream="$2"
  sqlite3 "$db" "SELECT COALESCE(SUM(input_tokens), 0) FROM usage WHERE stream_slug = '$stream';"
}

_usage_sum_output() {
  local db="$1" stream="$2"
  sqlite3 "$db" "SELECT COALESCE(SUM(output_tokens), 0) FROM usage WHERE stream_slug = '$stream';"
}

test_cumulative_first_log_stores_full_amount() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --model claude-opus-4-7 \
    --cumulative-in 10000 --cumulative-out 2000 \
    --stream login --type research >/dev/null

  local db="$dir/.ab/usage.db"
  [[ "$(_usage_row_count "$db" login)" == "1" ]] || fail "expected 1 row after first log"
  [[ "$(_usage_sum_input "$db" login)" == "10000" ]] || fail "expected input sum 10000"
  [[ "$(_usage_sum_output "$db" login)" == "2000" ]] || fail "expected output sum 2000"
}

test_cumulative_second_log_stores_only_delta() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  # First segment: cumulative 10k/2k (delta = 10k/2k since prior = 0)
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 10000 --cumulative-out 2000 \
    --stream login --type research >/dev/null
  # Second segment: cumulative 25k/5k (delta should be 15k/3k)
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 25000 --cumulative-out 5000 \
    --stream login --type implementation >/dev/null

  local db="$dir/.ab/usage.db"
  [[ "$(_usage_row_count "$db" login)" == "2" ]] || fail "expected 2 rows"
  # Sum across both rows MUST equal the latest cumulative value
  [[ "$(_usage_sum_input "$db" login)" == "25000" ]] || fail "expected sum == 25000, got $(_usage_sum_input "$db" login)"
  [[ "$(_usage_sum_output "$db" login)" == "5000" ]] || fail "expected sum == 5000, got $(_usage_sum_output "$db" login)"

  # Second row specifically holds the delta, not the cumulative
  local row2_in
  row2_in="$(sqlite3 "$db" "SELECT input_tokens FROM usage WHERE stream_slug='login' ORDER BY id DESC LIMIT 1;")"
  [[ "$row2_in" == "15000" ]] || fail "expected second row input=15000 (delta), got $row2_in"
}

test_cumulative_session_reset_logs_full_cumulative() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 30000 --cumulative-out 5000 \
    --stream login >/dev/null
  # Fresh CLI session (counter reset) — cumulative drops to 5000
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 5000 --cumulative-out 500 \
    --stream login >/dev/null

  local db="$dir/.ab/usage.db"
  local row2_in
  row2_in="$(sqlite3 "$db" "SELECT input_tokens FROM usage WHERE stream_slug='login' ORDER BY id DESC LIMIT 1;")"
  # Reset detected → log cumulative as-is
  [[ "$row2_in" == "5000" ]] || fail "expected reset to log cumulative=5000, got $row2_in"
}

test_cumulative_scope_is_per_stream() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  # Stream A uses 10k
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 10000 --cumulative-out 1000 \
    --stream stream-a >/dev/null
  # Stream B starts fresh — should not subtract stream-a's 10k
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 8000 --cumulative-out 800 \
    --stream stream-b >/dev/null

  local db="$dir/.ab/usage.db"
  local b_in
  b_in="$(sqlite3 "$db" "SELECT input_tokens FROM usage WHERE stream_slug='stream-b';")"
  [[ "$b_in" == "8000" ]] || fail "stream-b should log full 8000, got $b_in"
}

test_cumulative_scope_is_per_provider() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 10000 --cumulative-out 1000 \
    --stream login >/dev/null
  # Same stream, different provider — fresh session
  env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider codex --cumulative-in 7000 --cumulative-out 700 \
    --stream login >/dev/null

  local db="$dir/.ab/usage.db"
  local codex_in
  codex_in="$(sqlite3 "$db" "SELECT input_tokens FROM usage WHERE stream_slug='login' AND agent_provider='codex';")"
  [[ "$codex_in" == "7000" ]] || fail "codex row should log full 7000, got $codex_in"
}

test_cumulative_requires_both_flags() {
  _skip_unless_sqlite || return 0
  local dir output; dir="$(mktemp -d)"
  output="$(env HOME="$dir" "$TEST_ROOT/bin/ab" usage log \
    --provider claude --cumulative-in 10000 --stream login 2>&1 || true)"
  [[ "$output" == *"must be used together"* ]] \
    || fail "expected error about both flags required; got: $output"
}

test_checkpoint_forwards_cumulative_flags() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .
    git commit -m init >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )

  # First checkpoint with cumulative 12k/2k → should log 12k/2k
  (cd "$dir" && env HOME="$dir" "$TEST_ROOT/bin/ab" checkpoint login \
    --what "seg1" --next "seg2" \
    --cumulative-in 12000 --cumulative-out 2000 \
    --provider claude --model claude-sonnet-4-6 >/dev/null)

  # Second checkpoint with cumulative 30k/6k → delta 18k/4k
  (cd "$dir" && env HOME="$dir" "$TEST_ROOT/bin/ab" checkpoint login \
    --what "seg2" --next "seg3" \
    --cumulative-in 30000 --cumulative-out 6000 \
    --provider claude --model claude-sonnet-4-6 >/dev/null)

  local db="$dir/.ab/usage.db"
  local sum_in
  sum_in="$(sqlite3 "$db" "SELECT SUM(input_tokens) FROM usage WHERE stream_slug='login';")"
  [[ "$sum_in" == "30000" ]] || fail "expected sum=30000 (matches latest cumulative), got $sum_in"
  local row_count
  row_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE stream_slug='login';")"
  [[ "$row_count" == "2" ]] || fail "expected 2 rows, got $row_count"
}

test_checkpoint_rejects_mixing_delta_and_cumulative() {
  _skip_unless_sqlite || return 0
  local dir; dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .
    git commit -m init >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )

  local output
  output="$(cd "$dir" && env HOME="$dir" "$TEST_ROOT/bin/ab" checkpoint login \
    --what "x" --next "y" \
    --tokens-in 1000 --tokens-out 200 \
    --cumulative-in 5000 --cumulative-out 800 \
    --provider claude 2>&1 || true)"
  [[ "$output" == *"not both"* ]] \
    || fail "expected warning about mixing flags; got: $output"
}

for t in \
  test_cumulative_first_log_stores_full_amount \
  test_cumulative_second_log_stores_only_delta \
  test_cumulative_session_reset_logs_full_cumulative \
  test_cumulative_scope_is_per_stream \
  test_cumulative_scope_is_per_provider \
  test_cumulative_requires_both_flags \
  test_checkpoint_forwards_cumulative_flags \
  test_checkpoint_rejects_mixing_delta_and_cumulative; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
