#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_domain_slug_filters_and_branch_helpers() {
  ignore_bootstrap_domain_slug "features"
  if ignore_bootstrap_domain_slug "auth"; then
    fail "auth should be considered a real domain candidate"
  fi

  assert_eq "$(branch_to_stream_type "fix-auth-errors")" "bug"
  assert_eq "$(branch_to_stream_type "chore-cleanup")" "improvement"
  assert_eq "$(branch_to_stream_slug "feat-auth-session")" "auth-session"
  assert_eq "$(branch_to_stream_slug "main")" "main"
}

test_diff_signal_ignores_platform_noise() {
  local dir diff_text
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work" "$dir/src/features/auth"
  printf 'first\n' > "$dir/.platform/work/BRIEF.md"
  printf 'export const ready = true;\n' > "$dir/src/features/auth/index.ts"
  make_git_repo "$dir" "main"
  commit_all "$dir"

  printf 'platform-only\n' >> "$dir/.platform/work/BRIEF.md"
  printf 'export function normalizeAuthError() { return "fixed"; }\n' > "$dir/src/features/auth/index.ts"

  diff_text="$(repo_diff_signal_text "$dir")"
  assert_contains "$diff_text" "normalizeAuthError"
  assert_not_contains "$diff_text" "platform-only"
}

test_path_matching_and_stream_type_inference() {
  local domain_rows paths
  domain_rows=$'auth|frontend\nbilling|frontend\nauth|backend'
  paths=$'src/features/auth/errors.ts\nsrc/features/auth/login.tsx'

  assert_eq "$(best_domain_matches_for_paths "frontend" "$domain_rows" "$paths")" "auth"
  assert_eq "$(infer_stream_type_from_diff "" "$paths" "fix auth errors and null crashes")" "bug"
  assert_eq "$(infer_stream_type_from_diff "" "src/features/auth/refactor.ts" "refactor auth module")" "improvement"
  assert_eq "$(stream_slug_from_context $'auth' "bug" "$paths" "fix auth errors")" "auth-errors-fix"
}

test_domain_slug_filters_and_branch_helpers
test_diff_signal_ignores_platform_noise
test_path_matching_and_stream_type_inference
