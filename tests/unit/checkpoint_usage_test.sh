#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# These tests verify that checkpoint auto-logs a usage segment when token/
# provider flags are passed. They use an isolated HOME so the shared
# ~/.agentboard/usage.db is not touched.

setup_usage_fixture() {
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
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

run_checkpoint_with_usage() {
  local dir="$1"; shift
  (
    cd "$dir"
    unset AGENTBOARD_PROVIDER AGENTBOARD_SESSION_ID
    env HOME="$dir" "$TEST_ROOT/bin/agentboard" checkpoint login \
      --what "did the thing" --next "do the next" \
      "$@"
  )
}

test_checkpoint_auto_logs_when_full_flags_given() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  run_checkpoint_with_usage "$dir" \
    --tokens-in 12000 --tokens-out 2500 \
    --provider claude --model claude-sonnet-4-6 \
    --complexity normal >/dev/null

  local db="$dir/.agentboard/usage.db"
  [[ -f "$db" ]] || fail "usage.db was not created at $db"
  local count
  count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE stream_slug = 'login';" 2>/dev/null || echo 0)"
  [[ "$count" -ge 1 ]] || fail "expected ≥1 usage row for stream login, got $count"
  local total
  total="$(sqlite3 "$db" "SELECT total_tokens FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  [[ "$total" == "14500" ]] || fail "expected total_tokens=14500, got $total"
  local task_type complexity
  task_type="$(sqlite3 "$db" "SELECT task_type FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  complexity="$(sqlite3 "$db" "SELECT task_complexity FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  [[ "$task_type" == "chore" ]] || fail "expected inferred task_type=chore, got $task_type"
  [[ "$complexity" == "normal" ]] || fail "expected task_complexity=normal, got $complexity"
}

test_checkpoint_auto_logs_explicit_type_and_complexity() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  run_checkpoint_with_usage "$dir" \
    --tokens-in 8000 --tokens-out 1000 \
    --provider claude --model claude-sonnet-4-6 \
    --type implementation --complexity heavy >/dev/null

  local db="$dir/.agentboard/usage.db"
  local task_type complexity
  task_type="$(sqlite3 "$db" "SELECT task_type FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  complexity="$(sqlite3 "$db" "SELECT task_complexity FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  [[ "$task_type" == "implementation" ]] || fail "expected task_type=implementation, got $task_type"
  [[ "$complexity" == "heavy" ]] || fail "expected task_complexity=heavy, got $complexity"
}

test_checkpoint_infers_task_type_from_what() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  (
    cd "$dir"
    env HOME="$dir" "$TEST_ROOT/bin/agentboard" checkpoint login \
      --what "Debugged the save regression in ContactTab" \
      --next "Write the regression test" \
      --tokens-in 1200 --tokens-out 300 \
      --provider claude --model claude-sonnet-4-6 >/dev/null
  )

  local db="$dir/.agentboard/usage.db"
  local task_type
  task_type="$(sqlite3 "$db" "SELECT task_type FROM usage WHERE stream_slug = 'login' ORDER BY id DESC LIMIT 1;")"
  [[ "$task_type" == "debug" ]] || fail "expected inferred task_type=debug, got $task_type"
}

test_checkpoint_skips_logging_when_tokens_missing() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  run_checkpoint_with_usage "$dir" --provider claude >/dev/null

  local db="$dir/.agentboard/usage.db"
  if [[ -f "$db" ]]; then
    local count
    count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage;" 2>/dev/null || echo 0)"
    [[ "$count" == "0" ]] || fail "expected zero usage rows when tokens not provided, got $count"
  fi
}

test_checkpoint_skips_logging_without_provider() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  run_checkpoint_with_usage "$dir" --tokens-in 100 --tokens-out 50 >/dev/null

  local db="$dir/.agentboard/usage.db"
  if [[ -f "$db" ]]; then
    local count
    count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage;" 2>/dev/null || echo 0)"
    [[ "$count" == "0" ]] || fail "expected zero usage rows without --provider, got $count"
  fi
}

test_checkpoint_rejects_non_numeric_tokens() {
  local dir output
  dir="$(mktemp -d)"
  setup_usage_fixture "$dir"
  output="$(cd "$dir" && env HOME="$dir" "$TEST_ROOT/bin/agentboard" checkpoint login \
    --what "x" --next "y" \
    --tokens-in abc --tokens-out 100 --provider claude 2>&1 || true)"
  # Checkpoint itself succeeds; warning is printed. Verify the warning.
  if ! [[ "$output" == *"must be integers"* ]]; then
    fail "expected 'must be integers' warning, got: $output"
  fi
}

test_checkpoint_auto_logs_when_full_flags_given
test_checkpoint_auto_logs_explicit_type_and_complexity
test_checkpoint_infers_task_type_from_what
test_checkpoint_skips_logging_when_tokens_missing
test_checkpoint_skips_logging_without_provider
test_checkpoint_rejects_non_numeric_tokens
