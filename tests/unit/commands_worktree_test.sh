#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# Fixture: <base>/origin.git (bare) and <base>/proj (clone with main pushed).
# Sets WT_BASE and WT_REPO. Worktrees land in <base>, never in the real tmp root.
setup_worktree_fixture() {
  WT_BASE="$(mktemp -d)"
  WT_REPO="$WT_BASE/proj"
  mkdir -p "$WT_REPO"
  git init --bare -b main "$WT_BASE/origin.git" >/dev/null 2>&1
  make_git_repo "$WT_REPO" main
  printf 'one\n' > "$WT_REPO/a.txt"
  commit_all "$WT_REPO" initial
  git -C "$WT_REPO" remote add origin "$WT_BASE/origin.git"
  git -C "$WT_REPO" push -u origin main >/dev/null 2>&1
}

# Merge <branch> into main with a merge commit and push, as an MR would.
merge_branch_into_main() {
  local branch="$1"
  git -C "$WT_REPO" push -u origin "$branch" >/dev/null 2>&1
  git -C "$WT_REPO" checkout main >/dev/null 2>&1
  git -C "$WT_REPO" merge --no-ff "$branch" -m "merge $branch" >/dev/null 2>&1
  git -C "$WT_REPO" push origin main >/dev/null 2>&1
}

test_worktree_new_creates_sibling_on_feature_branch() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "feature/login"
  [[ -d "$WT_BASE/proj-login" ]] || fail "worktree folder was not created"
  assert_eq "$(git -C "$WT_BASE/proj-login" rev-parse --abbrev-ref HEAD)" "feature/login"
}

test_worktree_new_supports_bugfix_type_and_rejects_bad_slug() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new crash --type bugfix
  assert_status "$RUN_STATUS" 0
  assert_eq "$(git -C "$WT_BASE/proj-crash" rev-parse --abbrev-ref HEAD)" "bugfix/crash"
  run_cli_capture output "$WT_REPO" worktree new "Bad Slug"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "invalid slug should fail"
}

test_worktree_status_reports_fresh_for_new_branch() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new login
  run_cli_capture output "$WT_REPO" worktree status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "FRESH"
  assert_contains "$output" "feature/login"
}

test_worktree_status_reports_dirty_and_unpushed() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new dirty
  run_cli_capture output "$WT_REPO" worktree new ahead
  printf 'edit\n' >> "$WT_BASE/proj-dirty/a.txt"
  printf 'two\n' > "$WT_BASE/proj-ahead/b.txt"
  commit_all "$WT_BASE/proj-ahead" "local only"
  run_cli_capture output "$WT_REPO" worktree status
  assert_contains "$output" "DIRTY"
  assert_contains "$output" "UNPUSHED"
}

test_worktree_status_reports_missing_when_folder_removed() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new gone
  rm -rf "$WT_BASE/proj-gone"
  run_cli_capture output "$WT_REPO" worktree status
  assert_contains "$output" "MISSING"
}

test_worktree_clean_dry_run_keeps_merged_worktree() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new done
  printf 'two\n' > "$WT_BASE/proj-done/b.txt"
  commit_all "$WT_BASE/proj-done" "feature work"
  merge_branch_into_main feature/done
  run_cli_capture output "$WT_REPO" worktree status
  assert_contains "$output" "SAFE"
  run_cli_capture output "$WT_REPO" worktree clean
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "would remove"
  [[ -d "$WT_BASE/proj-done" ]] || fail "dry-run removed the worktree"
}

test_worktree_clean_apply_removes_only_safe() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new done
  run_cli_capture output "$WT_REPO" worktree new wip
  printf 'two\n' > "$WT_BASE/proj-done/b.txt"
  commit_all "$WT_BASE/proj-done" "feature work"
  printf 'three\n' > "$WT_BASE/proj-wip/c.txt"
  commit_all "$WT_BASE/proj-wip" "unmerged work"
  merge_branch_into_main feature/done
  printf 'edit\n' >> "$WT_BASE/proj-wip/a.txt"
  run_cli_capture output "$WT_REPO" worktree clean --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -d "$WT_BASE/proj-done" ]] || fail "merged worktree should be removed"
  [[ -d "$WT_BASE/proj-wip" ]] || fail "dirty/unpushed worktree must be kept"
  git -C "$WT_REPO" rev-parse -q --verify refs/heads/feature/done >/dev/null 2>&1 \
    && fail "merged branch should be deleted with its worktree"
  git -C "$WT_REPO" rev-parse -q --verify refs/heads/feature/wip >/dev/null 2>&1 \
    || fail "unmerged branch must be kept"
}

test_worktree_clean_never_removes_the_one_you_are_inside() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new done
  printf 'two\n' > "$WT_BASE/proj-done/b.txt"
  commit_all "$WT_BASE/proj-done" "feature work"
  merge_branch_into_main feature/done
  run_cli_capture output "$WT_BASE/proj-done" worktree clean --apply
  [[ -d "$WT_BASE/proj-done" ]] || fail "removed the worktree the command ran from"
}

test_worktree_root_scan_covers_every_repo() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree new login
  run_cli_capture output "$WT_BASE" worktree status --root "$WT_BASE"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "proj"
  assert_contains "$output" "feature/login"
}

test_worktree_status_without_worktrees_says_so() {
  local output
  setup_worktree_fixture
  run_cli_capture output "$WT_REPO" worktree status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No linked worktrees"
}

test_worktree_new_creates_sibling_on_feature_branch
test_worktree_new_supports_bugfix_type_and_rejects_bad_slug
test_worktree_status_reports_fresh_for_new_branch
test_worktree_status_reports_dirty_and_unpushed
test_worktree_status_reports_missing_when_folder_removed
test_worktree_clean_dry_run_keeps_merged_worktree
test_worktree_clean_apply_removes_only_safe
test_worktree_clean_never_removes_the_one_you_are_inside
test_worktree_root_scan_covers_every_repo
test_worktree_status_without_worktrees_says_so
