#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A git project plus synthetic Claude and Codex transcripts and an isolated db.
setup_ingest_fixture() {
  command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 not installed"; exit 0; }
  UI_DIR="$(mktemp -d)"
  printf '{}\n' > "$UI_DIR/package.json"
  make_git_repo "$UI_DIR" main
  commit_all "$UI_DIR" initial
  UI_DIR="$(cd "$UI_DIR" && pwd -P)"
  UI_BASE="$(mktemp -d)"
  export AGENTBOARD_USAGE_DB="$UI_BASE/usage.db"
  export AGENTBOARD_CLAUDE_DIR="$UI_BASE/claude"
  export AGENTBOARD_CODEX_DIR="$UI_BASE/codex"
  mkdir -p "$AGENTBOARD_CLAUDE_DIR" "$AGENTBOARD_CODEX_DIR"
  UI_ENC="$(printf '%s' "$UI_DIR" | sed 's/[^A-Za-z0-9]/-/g')"
  UI_CPROJ="$AGENTBOARD_CLAUDE_DIR/$UI_ENC"
  mkdir -p "$UI_CPROJ"
}

claude_line() { # id model day in cache_write cache_read out
  printf '{"type":"assistant","timestamp":"%sT10:00:00.000Z","cwd":"%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"output_tokens":%d,"output_tokens_details":{"thinking_tokens":5}}}}\n' \
    "$3" "$UI_DIR" "$1" "$2" "$4" "$5" "$6" "$7"
}

seed_claude_session() {
  local f="$UI_CPROJ/sess-1.jsonl"
  claude_line msg_A1 claude-test-1 2026-10-27 10 100 1000 20 >  "$f"
  claude_line msg_A1 claude-test-1 2026-10-27 10 100 1000 60 >> "$f"   # streamed duplicate: last wins
  claude_line msg_A3 claude-test-1 2026-10-27 5 0 500 20 >> "$f"
  claude_line msg_A2 claude-test-1 2026-10-28 1 0 200 10 >> "$f"
  claude_line msg_Z0 '<synthetic>' 2026-10-27 0 0 0 0 >> "$f"            # synthetic: ignored
  mkdir -p "$UI_CPROJ/sess-1/subagents"
  claude_line msg_S1 claude-test-2 2026-10-27 2 0 300 7 > "$UI_CPROJ/sess-1/subagents/agent-x.jsonl"
}

codex_tc() { # day input cached output reasoning
  printf '{"timestamp":"%sT10:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%d,"cached_input_tokens":%d,"cache_write_input_tokens":0,"output_tokens":%d,"reasoning_output_tokens":%d,"total_tokens":0}}}}\n' "$1" "$2" "$3" "$4" "$5"
}

seed_codex_session() {
  local d="$AGENTBOARD_CODEX_DIR/2026/10/27"; mkdir -p "$d"
  local f="$d/rollout-2026-10-27T10-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"
  printf '{"timestamp":"2026-10-27T10:00:00.000Z","type":"session_meta","payload":{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","cwd":"%s"}}\n' "$UI_DIR" > "$f"
  printf '{"timestamp":"2026-10-27T10:00:01.000Z","type":"turn_context","payload":{"model":"gpt-test-1"}}\n' >> "$f"
  printf '{"timestamp":"2026-10-27T10:04:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}\n' >> "$f"
  codex_tc 2026-10-27 1000 800 100 10 >> "$f"
  codex_tc 2026-10-27 1000 800 100 10 >> "$f"       # repeated event: delta 0
  codex_tc 2026-10-27 2500 2000 250 30 >> "$f"
  printf '{"timestamp":"2026-10-28T09:00:00.000Z","type":"turn_context","payload":{"model":"gpt-test-2"}}\n' >> "$f"
  codex_tc 2026-10-28 3000 2300 300 40 >> "$f"
}

q() { sqlite3 "$AGENTBOARD_USAGE_DB" "$1"; }

test_claude_ingest_dedupes_streamed_messages_and_includes_subagents() {
  local output
  setup_ingest_fixture; seed_claude_session
  run_cli_capture output "$UI_DIR" usage ingest
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Ingested"
  # sess-1 / claude-test-1 / 2026-10-27: A1(final 60) + A3 -> in 15, cw 100, cr 1500, out 80
  assert_eq "$(q "select input_tokens||'/'||cache_write_tokens||'/'||cache_read_tokens||'/'||output_tokens from usage where model='claude-test-1' and day='2026-10-27'")" "15/100/1500/80"
  # next day is its own row
  assert_eq "$(q "select input_tokens||'/'||cache_read_tokens||'/'||output_tokens from usage where model='claude-test-1' and day='2026-10-28'")" "1/200/10"
  # subagent tokens belong to the parent session
  assert_eq "$(q "select session_id||':'||cache_read_tokens from usage where model='claude-test-2'")" "sess-1:300"
  assert_eq "$(q "select count(*) from usage where model like '<%'")" "0"
  assert_eq "$(q "select total_tokens from usage where model='claude-test-1' and day='2026-10-27'")" "1695"
}

test_codex_ingest_sums_deltas_per_model_and_day() {
  local output
  setup_ingest_fixture; seed_codex_session
  run_cli_capture output "$UI_DIR" usage ingest
  assert_status "$RUN_STATUS" 0
  # gpt-test-1 on 10-27: fresh (2500-2000)=500, cache read 2000, out 250
  assert_eq "$(q "select input_tokens||'/'||cache_read_tokens||'/'||output_tokens||'/'||reasoning_tokens from usage where model='gpt-test-1'")" "500/2000/250/30"
  # gpt-test-2 on 10-28: only the delta since the previous total
  assert_eq "$(q "select input_tokens||'/'||cache_read_tokens||'/'||output_tokens from usage where model='gpt-test-2' and day='2026-10-28'")" "200/300/50"
  assert_eq "$(q "select session_id from usage where model='gpt-test-1'")" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  assert_eq "$(q "select repo from usage where model='gpt-test-1'")" "$(basename "$UI_DIR")"
}

test_codex_counter_reset_is_not_counted_as_negative() {
  local output f
  setup_ingest_fixture
  local d="$AGENTBOARD_CODEX_DIR/2026/10/27"; mkdir -p "$d"
  f="$d/rollout-2026-10-27T10-00-00-11111111-2222-3333-4444-555555555555.jsonl"
  printf '{"timestamp":"2026-10-27T10:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"%s"}}\n' "$UI_DIR" > "$f"
  printf '{"timestamp":"2026-10-27T10:00:01.000Z","type":"turn_context","payload":{"model":"gpt-test-1"}}\n' >> "$f"
  codex_tc 2026-10-27 1000 800 100 0 >> "$f"
  codex_tc 2026-10-27 200 100 20 0 >> "$f"          # counters restarted (e.g. after compaction)
  run_cli_capture output "$UI_DIR" usage ingest
  assert_eq "$(q "select input_tokens||'/'||cache_read_tokens||'/'||output_tokens from usage where model='gpt-test-1'")" "300/900/120"
}

test_ingest_is_idempotent_and_keeps_manual_annotations() {
  local output
  setup_ingest_fixture; seed_claude_session
  run_cli_capture output "$UI_DIR" usage ingest
  q "update usage set task_type='debug', stream_slug='login' where model='claude-test-1' and day='2026-10-27'"
  run_cli_capture output "$UI_DIR" usage ingest
  assert_eq "$(q "select count(*) from usage")" "3"
  assert_eq "$(q "select task_type||'/'||stream_slug from usage where model='claude-test-1' and day='2026-10-27'")" "debug/login"
  assert_eq "$(q "select sum(total_tokens) from usage")" "$((1695 + 211 + 309))"
}

test_ingest_dry_run_writes_nothing() {
  local output
  setup_ingest_fixture; seed_claude_session
  run_cli_capture output "$UI_DIR" usage ingest --dry-run
  assert_contains "$output" "dry run"
  assert_eq "$(q "select count(*) from usage")" "0"
}

test_ingest_is_scoped_to_the_current_project_unless_all() {
  local output other
  setup_ingest_fixture; seed_claude_session
  other="$AGENTBOARD_CLAUDE_DIR/-some-other-project"; mkdir -p "$other"
  claude_line msg_O1 claude-test-9 2026-10-27 1 0 1 1 > "$other/sess-9.jsonl"
  run_cli_capture output "$UI_DIR" usage ingest
  assert_eq "$(q "select count(*) from usage where model='claude-test-9'")" "0"
  run_cli_capture output "$UI_DIR" usage ingest --all
  assert_eq "$(q "select count(*) from usage where model='claude-test-9'")" "1"
}

test_ingest_since_skips_older_days() {
  local output
  setup_ingest_fixture; seed_claude_session
  run_cli_capture output "$UI_DIR" usage ingest --since 2026-10-28
  assert_eq "$(q "select count(*) from usage where day='2026-10-27'")" "0"
  assert_eq "$(q "select count(*) from usage where day='2026-10-28'")" "1"
}

test_report_groups_by_model_and_shows_cache_hit_rate() {
  local output
  setup_ingest_fixture; seed_claude_session; seed_codex_session
  run_cli_capture output "$UI_DIR" usage ingest
  run_cli_capture output "$UI_DIR" usage report --days 3650 --by model
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "claude-test-1"
  assert_contains "$output" "gpt-test-1"
  assert_contains "$output" "Cache%"
  assert_contains "$output" "Overall:"
  run_cli_capture output "$UI_DIR" usage report --days 3650 --by provider
  assert_contains "$output" "claude"
  assert_contains "$output" "codex"
}

test_report_with_no_data_points_at_ingest() {
  local output
  setup_ingest_fixture
  run_cli_capture output "$UI_DIR" usage report
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab usage ingest"
}

test_report_cost_needs_user_prices_and_uses_longest_prefix() {
  local output prices
  setup_ingest_fixture; seed_claude_session
  run_cli_capture output "$UI_DIR" usage ingest
  prices="$UI_BASE/pricing.tsv"
  run_cli_capture output "$UI_DIR" usage report --days 3650 --cost
  assert_contains "$output" "No prices configured"
  export AGENTBOARD_PRICING="$prices"
  printf 'claude\t1\t1\t1\t1\nclaude-test-1\t10\t20\t0\t0\n' > "$prices"
  run_cli_capture output "$UI_DIR" usage report --days 3650 --cost
  unset AGENTBOARD_PRICING
  assert_contains "$output" "claude-test-1"
  # claude-test-1: fresh 16 in @10 + out 90 @20 per 1M; claude-test-2 falls back to prefix "claude" @1
  assert_contains "$output" "TOTAL (priced models)"
  assert_not_contains "$output" "no price for this model"
}

test_migrate_folds_the_legacy_db_once_and_keeps_a_backup() {
  local output home
  setup_ingest_fixture
  unset AGENTBOARD_USAGE_DB
  home="$(mktemp -d)"; mkdir -p "$home/.agentboard"
  sqlite3 "$home/.agentboard/usage.db" "CREATE TABLE usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp DATETIME, agent_provider TEXT NOT NULL, model TEXT, stream_slug TEXT, repo TEXT, task_type TEXT, input_tokens INTEGER, output_tokens INTEGER, total_tokens INTEGER, estimated_cost REAL, note TEXT, session_id TEXT, task_complexity TEXT);
    INSERT INTO usage (timestamp, agent_provider, model, repo, task_type, input_tokens, output_tokens, total_tokens) VALUES ('2026-04-16 13:21:16','codex','gpt-5.4','proj','audit',95000,18000,113000);"
  run_and_capture output env HOME="$home" "$TEST_ROOT/bin/ab" usage migrate
  assert_status "$RUN_STATUS" 0
  [[ -f "$home/.agentboard/usage.db.merged" ]] || fail "legacy db should be kept as .merged"
  assert_eq "$(sqlite3 "$home/.ab/usage.db" "select count(*)||':'||source from usage")" "1:manual"
  run_and_capture output env HOME="$home" "$TEST_ROOT/bin/ab" usage migrate
  assert_eq "$(sqlite3 "$home/.ab/usage.db" "select count(*) from usage")" "1"
}

test_close_ingests_this_projects_usage_automatically() {
  local output
  setup_ingest_fixture; seed_claude_session
  ( cd "$UI_DIR" && init_project_fixture "$UI_DIR" && git add -A && git commit -qm init \
    && "$TEST_ROOT/bin/ab" new-domain auth api >/dev/null && "$TEST_ROOT/bin/ab" new-stream login --domain auth --base-branch main --branch feat/login >/dev/null )
  awk '/^closure_approved:/ { print "closure_approved: true"; next } { print }' "$UI_DIR/.platform/work/login.md" > "$UI_BASE/s.md" && mv "$UI_BASE/s.md" "$UI_DIR/.platform/work/login.md"
  run_cli_capture output "$UI_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_eq "$(q "select count(*) from usage where source='ingest'")" "3"
}

test_claude_ingest_dedupes_streamed_messages_and_includes_subagents
test_codex_ingest_sums_deltas_per_model_and_day
test_codex_counter_reset_is_not_counted_as_negative
test_ingest_is_idempotent_and_keeps_manual_annotations
test_ingest_dry_run_writes_nothing
test_ingest_is_scoped_to_the_current_project_unless_all
test_ingest_since_skips_older_days
test_report_groups_by_model_and_shows_cache_hit_rate
test_report_with_no_data_points_at_ingest
test_report_cost_needs_user_prices_and_uses_longest_prefix
test_migrate_folds_the_legacy_db_once_and_keeps_a_backup
test_close_ingests_this_projects_usage_automatically
