#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

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

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_new_stream_requires_platform_dir() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main

  run_cli_capture output "$dir" new-stream auth-fix --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Run 'ab init' first"
}

test_new_stream_requires_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Usage: ab new-stream"
}

test_new_stream_rejects_uppercase_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream AuthFix --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Stream slug must be kebab-case"
}

test_new_stream_rejects_underscore_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth_fix --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Stream slug must be kebab-case"
}

test_new_stream_rejects_leading_dash_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream -auth-fix --domain auth
  assert_status "$RUN_STATUS" 1
  # Leading dash makes it look like a flag; either usage error or "unknown flag"
  assert_eq "$RUN_STATUS" "1"
}

test_new_stream_requires_at_least_one_domain() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth-fix
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires at least one --domain"
}

test_new_stream_rejects_domain_flag_with_no_value() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth-fix --domain
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires a value after --domain"
}

test_new_stream_rejects_repo_flag_with_no_value() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (cd "$dir"; "$TEST_ROOT/bin/ab" new-domain auth >/dev/null)

  run_cli_capture output "$dir" new-stream auth-fix --domain auth --repo
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires a value after --repo"
}

test_new_stream_rejects_base_branch_flag_with_no_value() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  init_project_fixture "$dir"
  commit_all "$dir" "init"

  (cd "$dir"; "$TEST_ROOT/bin/ab" new-domain api >/dev/null)

  run_cli_capture output "$dir" new-stream api-fix --domain api --base-branch
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires a value after --base-branch"
}

test_new_stream_rejects_branch_flag_with_no_value() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  init_project_fixture "$dir"
  commit_all "$dir" "init"

  (cd "$dir"; "$TEST_ROOT/bin/ab" new-domain api >/dev/null)

  run_cli_capture output "$dir" new-stream api-fix --domain api --branch
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "requires a value after --branch"
}

test_new_stream_rejects_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (cd "$dir"; "$TEST_ROOT/bin/ab" new-domain auth >/dev/null)

  run_cli_capture output "$dir" new-stream auth-fix --domain auth --bogus value
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown flag for new-stream"
}

test_new_stream_rejects_positional_arg_after_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (cd "$dir"; "$TEST_ROOT/bin/ab" new-domain auth >/dev/null)

  # Unlike new-domain, new-stream does not accept positional repo args
  run_cli_capture output "$dir" new-stream auth-fix extra-positional --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown flag for new-stream"
}

test_new_stream_rejects_non_kebab_domain_value() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" new-stream auth-fix --domain "Auth_Module"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Domain slug 'Auth_Module' must be kebab-case"
}

# ---------------------------------------------------------------------------
# Idempotency / collision
# ---------------------------------------------------------------------------

test_new_stream_rejects_duplicate_slug() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  run_cli_capture output "$dir" new-stream auth-fix --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "already exists"
}

test_new_stream_rejects_duplicate_active_row() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
    # Manually remove the stream file so only the ACTIVE.md row remains,
    # simulating a partial state where the file was deleted but row persists.
    rm ".platform/work/auth-fix.md"
  )

  run_cli_capture output "$dir" new-stream auth-fix --domain auth
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "already has a row for"
}

# ---------------------------------------------------------------------------
# Default values contract
# ---------------------------------------------------------------------------

test_new_stream_defaults_type_to_feature() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "type: feature"
}

test_new_stream_defaults_agent_to_codex() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "agent_owner: codex"
}

test_new_stream_defaults_repo_to_repo_primary() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "repo_ids: [repo-primary]"
}

test_new_stream_sets_stream_id() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "stream_id: stream-auth-fix"
}

test_new_stream_sets_created_at_to_today() {
  local dir today_str
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  today_str="$(date +%F)"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "created_at: $today_str"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "updated_at: $today_str"
}

test_new_stream_active_row_format() {
  local dir today_str
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  today_str="$(date +%F)"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| auth-fix | feature | planning | codex |"
}

test_new_stream_branch_defaults_no_git_repo() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  # Deliberately do NOT init a git repo — exercises the "no git" fallback path
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  # Without a git repo, base_branch falls back to "develop" and git_branch to "feature/<slug>"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "base_branch: develop"
  assert_file_contains "$dir/.platform/work/auth-fix.md" "git_branch: feature/auth-fix"
}

# ---------------------------------------------------------------------------
# Custom values flow through
# ---------------------------------------------------------------------------

test_new_stream_custom_type_and_agent() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain billing >/dev/null
    "$TEST_ROOT/bin/ab" new-stream billing-fix \
      --domain billing --type bug --agent claude-code >/dev/null
  )

  assert_file_contains "$dir/.platform/work/billing-fix.md" "type: bug"
  assert_file_contains "$dir/.platform/work/billing-fix.md" "agent_owner: claude-code"
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "| billing-fix | bug | planning | claude-code |"
}

# ---------------------------------------------------------------------------
# Multi-value and deduplication
# ---------------------------------------------------------------------------

test_new_stream_multiple_repos_written_correctly() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix \
      --domain auth --repo backend --repo frontend >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "repo_ids: [backend, frontend]"
}

test_new_stream_deduplicates_repeated_repo() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix \
      --domain auth --repo backend --repo backend >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "repo_ids: [backend]"
}

test_new_stream_deduplicates_repeated_domain() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix \
      --domain auth --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/auth-fix.md" "domain_slugs: [auth]"
}

# ---------------------------------------------------------------------------
# ACTIVE.md placeholder replacement
# ---------------------------------------------------------------------------

test_new_stream_replaces_none_placeholder_in_active() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  # Baseline: placeholder row exists before any stream is created
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "_(none)_"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  # The stream row is present; the placeholder row must be gone
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "auth-fix"
  assert_file_not_contains "$dir/.platform/work/ACTIVE.md" "_(none)_"
}

# ---------------------------------------------------------------------------
# BRIEF.md behaviour
# ---------------------------------------------------------------------------

test_new_stream_populates_brief_for_first_stream() {
  local dir
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
  )

  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Feature:** auth-fix"
  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Stream file:** \`work/auth-fix.md\`"
}

test_new_stream_preserves_real_brief_and_warns() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  # Prime a first stream so BRIEF.md gets a real (non-placeholder) feature name
  (
    cd "$dir"
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream auth-fix --domain auth >/dev/null
    # Replace the TODO placeholder lines with real content so it is no longer
    # considered a placeholder by brief_is_placeholder()
    local tmp; tmp="$(mktemp)"
    awk '/_not yet set — fill this in when you start your first workstream_/ { print "**Feature:** auth-fix"; next } { print }' \
      ".platform/work/BRIEF.md" > "$tmp"
    mv "$tmp" ".platform/work/BRIEF.md"
    "$TEST_ROOT/bin/ab" new-domain billing >/dev/null
  )

  run_cli_capture output "$dir" new-stream billing-fix --domain billing
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "BRIEF.md was left untouched"
  # Existing content must not have been overwritten
  assert_file_contains "$dir/.platform/work/BRIEF.md" "**Feature:** auth-fix"
  assert_file_not_contains "$dir/.platform/work/BRIEF.md" "**Feature:** billing-fix"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------

test_new_stream_requires_platform_dir
test_new_stream_requires_slug
test_new_stream_rejects_uppercase_slug
test_new_stream_rejects_underscore_slug
test_new_stream_rejects_leading_dash_slug
test_new_stream_requires_at_least_one_domain
test_new_stream_rejects_domain_flag_with_no_value
test_new_stream_rejects_repo_flag_with_no_value
test_new_stream_rejects_base_branch_flag_with_no_value
test_new_stream_rejects_branch_flag_with_no_value
test_new_stream_rejects_unknown_flag
test_new_stream_rejects_positional_arg_after_slug
test_new_stream_rejects_non_kebab_domain_value
test_new_stream_rejects_duplicate_slug
test_new_stream_rejects_duplicate_active_row
test_new_stream_defaults_type_to_feature
test_new_stream_defaults_agent_to_codex
test_new_stream_defaults_repo_to_repo_primary
test_new_stream_sets_stream_id
test_new_stream_sets_created_at_to_today
test_new_stream_active_row_format
test_new_stream_branch_defaults_no_git_repo
test_new_stream_custom_type_and_agent
test_new_stream_multiple_repos_written_correctly
test_new_stream_deduplicates_repeated_repo
test_new_stream_deduplicates_repeated_domain
test_new_stream_replaces_none_placeholder_in_active
test_new_stream_populates_brief_for_first_stream
test_new_stream_preserves_real_brief_and_warns
