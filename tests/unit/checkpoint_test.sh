#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_checkpoint_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth \
      --base-branch main --branch feat/login >/dev/null
  )
}

test_template_has_resume_state_section() {
  local template="$TEST_ROOT/templates/platform/work/TEMPLATE.md"
  assert_file_contains "$template" "## Resume state"
  assert_file_contains "$template" "**Last updated:**"
  assert_file_contains "$template" "**What just happened:**"
  assert_file_contains "$template" "**Current focus:**"
  assert_file_contains "$template" "**Next action:**"
  assert_file_contains "$template" "**Blockers:**"
}

test_new_stream_includes_resume_state() {
  local dir stream_file
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  assert_file_contains "$stream_file" "## Resume state"
  assert_file_contains "$stream_file" "**Next action:**"
}

test_checkpoint_requires_what() {
  local dir output
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  run_cli_capture output "$dir" checkpoint login --next "do the next thing"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires --what"
}

test_checkpoint_requires_next() {
  local dir output
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  run_cli_capture output "$dir" checkpoint login --what "finished the thing"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires --next"
}

test_checkpoint_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  run_cli_capture output "$dir" checkpoint --what "x" --next "y"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Usage: ab checkpoint"
}

test_checkpoint_rejects_missing_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  run_cli_capture output "$dir" checkpoint nonexistent --what "x" --next "y"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not found"
}

test_checkpoint_overwrites_resume_state() {
  local dir output stream_file
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  run_cli_capture output "$dir" checkpoint login \
    --what "wired the webhook handler" \
    --next "add integration tests"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Checkpoint saved"

  assert_file_contains "$stream_file" "wired the webhook handler"
  assert_file_contains "$stream_file" "add integration tests"
  # Placeholder was replaced, not appended
  assert_file_not_contains "$stream_file" "**What just happened:** _not set_"
  assert_file_not_contains "$stream_file" "**Next action:** _not set_"
}

test_checkpoint_is_idempotent_no_duplicate_sections() {
  local dir stream_file count
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  run_cli_capture _out "$dir" checkpoint login --what "first" --next "second"
  run_cli_capture _out "$dir" checkpoint login --what "third" --next "fourth"
  run_cli_capture _out "$dir" checkpoint login --what "fifth" --next "sixth"

  count="$(grep -c '^## Resume state' "$stream_file")"
  assert_eq "$count" "1"

  # Last-writer-wins: most recent --what is in the file, earlier ones are not
  assert_file_contains "$stream_file" "**What just happened:** fifth"
  assert_file_not_contains "$stream_file" "**What just happened:** first"
  assert_file_not_contains "$stream_file" "**What just happened:** third"
}

test_checkpoint_prepends_progress_log_entry() {
  local dir stream_file
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  run_cli_capture _out "$dir" checkpoint login --what "did thing A" --next "do thing B"
  assert_file_contains "$stream_file" "did thing A"
}

test_checkpoint_trims_progress_log_to_last_10() {
  local dir stream_file entries
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    run_cli_capture _out "$dir" checkpoint login \
      --what "entry number $i" --next "continue from $i"
  done

  # Only 10 entries should remain. Count lines matching the YYYY-MM-DD HH:MM prefix
  # inside the Progress log section.
  entries="$(awk '
    /^## Progress log/ { in_log = 1; next }
    in_log && /^## / { exit }
    in_log && /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} —/ { print }
  ' "$stream_file" | wc -l | tr -d ' ')"
  assert_eq "$entries" "10"

  # The most recent entry is kept, the oldest has been trimmed
  assert_file_contains "$stream_file" "entry number 12"
  assert_file_not_contains "$stream_file" "entry number 1 "
  assert_file_not_contains "$stream_file" "entry number 2 "
}

test_checkpoint_updates_frontmatter_updated_at() {
  local dir stream_file today_str
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  today_str="$(date +%F)"

  run_cli_capture _out "$dir" checkpoint login --what "x" --next "y"
  assert_file_contains "$stream_file" "updated_at: $today_str"
}

test_checkpoint_dry_run_does_not_write() {
  local dir stream_file before after
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  before="$(shasum "$stream_file" | awk '{print $1}')"

  run_cli_capture output "$dir" checkpoint login \
    --what "dry test" --next "dry next" --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Would update"
  assert_contains "$output" "dry test"

  after="$(shasum "$stream_file" | awk '{print $1}')"
  assert_eq "$after" "$before"
}

test_checkpoint_blocker_and_focus() {
  local dir stream_file
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"

  run_cli_capture _out "$dir" checkpoint login \
    --what "stuck" --next "unblock" \
    --blocker "waiting on API keys" --focus "src/auth.ts:42"
  assert_file_contains "$stream_file" "**Blockers:** waiting on API keys"
  assert_file_contains "$stream_file" "**Current focus:** src/auth.ts:42"
}

test_checkpoint_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_checkpoint_fixture "$dir"
  run_cli_capture output "$dir" checkpoint --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: ab checkpoint"
  assert_contains "$output" "--what"
  assert_contains "$output" "--next"
}

test_template_has_resume_state_section
test_new_stream_includes_resume_state
test_checkpoint_requires_what
test_checkpoint_requires_next
test_checkpoint_requires_slug
test_checkpoint_rejects_missing_stream
test_checkpoint_overwrites_resume_state
test_checkpoint_is_idempotent_no_duplicate_sections
test_checkpoint_prepends_progress_log_entry
test_checkpoint_trims_progress_log_to_last_10
test_checkpoint_updates_frontmatter_updated_at
test_checkpoint_dry_run_does_not_write
test_checkpoint_blocker_and_focus
test_checkpoint_help
