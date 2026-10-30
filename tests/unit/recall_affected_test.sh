#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_affected_fixture() {
  AF="$(mktemp -d)"
  make_git_repo "$AF" main
  mkdir -p "$AF/src/forms" "$AF/src/api" "$AF/.platform/domains"
  printf 'x\n' > "$AF/src/forms/FormView.tsx"; printf 'x\n' > "$AF/src/api/client.ts"
  printf -- '---\nslug: forms\nrepo_ids: [x]\nupdated_at: 2026-10-01\n---\n\n# Domain: forms\n\n- View: `src/forms/FormView.tsx`\n' > "$AF/.platform/domains/forms.md"
  printf -- '---\nslug: api\nrepo_ids: [x]\nupdated_at: 2026-10-01\n---\n\n# Domain: api\n\n- Client: `src/api/client.ts`\n' > "$AF/.platform/domains/api.md"
  commit_all "$AF" initial
  AF="$(cd "$AF" && pwd -P)"
}

test_affected_since_a_date_uses_each_repos_last_commit_before_it() {
  local out
  setup_affected_fixture
  git -C "$AF" commit -q --allow-empty --date="2020-01-01T00:00:00" -m old >/dev/null 2>&1 || true
  printf 'changed\n' >> "$AF/src/api/client.ts"; git -C "$AF" commit -qam "later change"
  run_cli_capture out "$AF" recall --affected --since 2999-01-01
  assert_contains "$out" "Nothing changed"
  run_cli_capture out "$AF" recall --affected --since 1990-01-01
  assert_status "$RUN_STATUS" 0
}

test_affected_lists_cards_naming_a_changed_file_and_new_uncovered_files() {
  local out
  setup_affected_fixture
  printf 'changed\n' >> "$AF/src/forms/FormView.tsx"            # uncommitted edit to a named file
  mkdir -p "$AF/src/reports"; printf 'new\n' > "$AF/src/reports/Chart.tsx"   # brand-new, unnamed file
  run_cli_capture out "$AF" recall --affected
  assert_status "$RUN_STATUS" 0
  assert_contains "$out" "forms"; assert_contains "$out" "src/forms/FormView.tsx"
  assert_not_contains "$out" "api  "
  assert_contains "$out" "no card mentions"; assert_contains "$out" "src/reports"
}

test_affected_is_quiet_about_a_card_updated_in_the_same_change() {
  local out
  setup_affected_fixture
  printf 'changed\n' >> "$AF/src/forms/FormView.tsx"
  printf '\n- also noted\n' >> "$AF/.platform/domains/forms.md"
  run_cli_capture out "$AF" recall --affected
  assert_contains "$out" "No un-updated card names a file you changed"
  assert_contains "$out" "already updated"
}

test_affected_sees_a_committed_change_against_an_explicit_base_and_deleted_files() {
  local out
  setup_affected_fixture
  git -C "$AF" rm -q src/api/client.ts; git -C "$AF" commit -q -m "drop client"
  run_cli_capture out "$AF" recall --affected HEAD~1
  assert_contains "$out" "api"; assert_contains "$out" "src/api/client.ts"
}

test_affected_quiet_prints_one_line_only_when_a_card_needs_a_look() {
  local out
  setup_affected_fixture
  run_cli_capture out "$AF" recall --affected --quiet; assert_eq "$out" ""
  printf 'changed\n' >> "$AF/src/api/client.ts"
  run_cli_capture out "$AF" recall --affected --quiet
  assert_contains "$out" "card(s): api"
  [[ "$(printf '%s\n' "$out" | grep -c .)" == 1 ]] || fail "quiet mode must be one line"
}

test_affected_with_no_changes_says_so_and_ignores_platform_files() {
  local out
  setup_affected_fixture
  run_cli_capture out "$AF" recall --affected; assert_contains "$out" "Nothing changed"
  printf 'n\n' >> "$AF/.platform/domains/api.md"
  run_cli_capture out "$AF" recall --affected; assert_contains "$out" "Nothing changed"
}

test_post_commit_hook_nudges_when_a_commit_touches_a_named_file_without_updating_the_card() {
  local out
  setup_affected_fixture
  mkdir -p "$AF/.platform/memory"; printf -- '---\n' > "$AF/.platform/memory/log.md"; commit_all "$AF" "add log"
  export PATH="$TEST_ROOT/bin:$PATH"
  printf 'changed\n' >> "$AF/src/api/client.ts"; git -C "$AF" commit -qam "tweak client"
  out="$(cd "$AF" && bash "$TEST_ROOT/templates/platform/scripts/hooks/post-commit" 2>&1)"
  assert_contains "$out" "card(s): api"
  printf 'more\n' >> "$AF/src/api/client.ts"; printf '\n- note\n' >> "$AF/.platform/domains/api.md"; git -C "$AF" commit -qam "tweak client + card"
  out="$(cd "$AF" && bash "$TEST_ROOT/templates/platform/scripts/hooks/post-commit" 2>&1)"
  assert_not_contains "$out" "card(s)"
}

test_affected_lists_cards_naming_a_changed_file_and_new_uncovered_files
test_affected_is_quiet_about_a_card_updated_in_the_same_change
test_affected_sees_a_committed_change_against_an_explicit_base_and_deleted_files
test_affected_quiet_prints_one_line_only_when_a_card_needs_a_look
test_affected_with_no_changes_says_so_and_ignores_platform_files
test_post_commit_hook_nudges_when_a_commit_touches_a_named_file_without_updating_the_card
test_affected_since_a_date_uses_each_repos_last_commit_before_it
