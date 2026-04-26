#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_new_domain_new_stream_resolve_and_handoff() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth backend --repo frontend >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth --type bug --agent codex --repo backend --repo frontend >/dev/null
  )

  assert_file_contains "$dir/.platform/domains/auth.md" "repo_ids: [backend, frontend]"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "stream_id: stream-auth-fix"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "repo_ids: [backend, frontend]"
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| auth-fix | bug | planning | codex |"
  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Feature:** auth-fix"

  run_cli_capture output "$dir" resolve auth-fix
  assert_contains "$output" "type: stream"
  assert_contains "$output" "id:   stream-auth-fix"

  run_cli_capture output "$dir" handoff auth-fix
  assert_contains "$output" "Load in this order:"
  assert_contains "$output" ".platform/work/auth-fix.md"
  assert_contains "$output" "Repos in scope:"
}

test_new_stream_rejects_unknown_domain() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth-fix --domain missing-domain
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "./.platform/domains/missing-domain.md does not exist. Create the domain first."
}

test_new_stream_branch_flags_written_to_frontmatter() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  init_project_fixture "$dir"
  commit_all "$dir" "init"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain api >/dev/null
    "$TEST_ROOT/bin/ab" new-stream api-v2 \
      --domain api \
      --base-branch develop \
      --branch feature/api-v2 >/dev/null
  )

  assert_file_contains "$dir/.platform/work/api-v2.md" "base_branch: develop"
  assert_file_contains "$dir/.platform/work/api-v2.md" "git_branch: feature/api-v2"
}

test_new_stream_branch_defaults_when_flags_omitted() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  init_project_fixture "$dir"
  commit_all "$dir" "init"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain api >/dev/null
    # No --base-branch / --branch: non-interactive fallback uses current branch
    "$TEST_ROOT/bin/ab" new-stream api-v3 --domain api >/dev/null
  )

  assert_file_contains "$dir/.platform/work/api-v3.md" "base_branch:"
  assert_file_contains "$dir/.platform/work/api-v3.md" "git_branch:"
}

test_handoff_shows_branch_info() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  init_project_fixture "$dir"
  commit_all "$dir" "init"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain api >/dev/null
    "$TEST_ROOT/bin/ab" new-stream api-v2 \
      --domain api \
      --base-branch develop \
      --branch feature/api-v2 >/dev/null
  )

  run_cli_capture output "$dir" handoff api-v2
  assert_contains "$output" "feature/api-v2"
  assert_contains "$output" "develop"
  assert_contains "$output" "git checkout"
}

test_new_stream_refreshes_invalid_brief_reference() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  local tmp
  tmp="$(mktemp)"
  awk '
    { gsub(/\*\*Feature:\*\* _not yet set — fill this in when you start your first workstream_/, "**Feature:** closed-stream") }
    { gsub(/\*\*Stream file:\*\* `work\/<slug>\.md`/, "**Stream file:** `work/closed-stream.md`") }
    { print }
  ' "$dir/.platform/work/BRIEF.md" > "$tmp"
  mv "$tmp" "$dir/.platform/work/BRIEF.md"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Feature:** auth-fix"
  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Stream file:** \`work/auth-fix.md\`"
}

test_current_stream_and_next_action_commands() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-domain billing >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream billing-fix --domain billing >/dev/null
    tmp="$(mktemp)"
    awk '
      /^\- \*\*Next action:\*\* _not set_$/ && !done {
        print "- **Next action:** Verify the billing handoff path."
        done = 1
        next
      }
      { print }
    ' ".platform/work/billing-fix.md" > "$tmp"
    mv "$tmp" ".platform/work/billing-fix.md"
  )

  run_cli_capture output "$dir" current-stream --quiet
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "auth-fix"

  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| auth-fix | feature | planning | codex |"
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| billing-fix | feature | planning | codex |"

  run_cli_capture output "$dir" current-stream --stream billing-fix --session-id sess-99 --remember --quiet
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "billing-fix"

  run_cli_capture output "$dir" current-stream --session-id sess-99 --quiet
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "billing-fix"

  run_cli_capture output "$dir" next-action billing-fix --quiet
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Verify the billing handoff path."
}

test_new_domain_new_stream_resolve_and_handoff
test_new_stream_rejects_unknown_domain
test_new_stream_branch_flags_written_to_frontmatter
test_new_stream_branch_defaults_when_flags_omitted
test_handoff_shows_branch_info
test_new_stream_refreshes_invalid_brief_reference
test_current_stream_and_next_action_commands
