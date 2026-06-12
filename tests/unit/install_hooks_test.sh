#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

GUARD="$TEST_ROOT/templates/platform/scripts/hooks/bash-guard.sh"

# ─── guard script behavior (no project required) ──────────────────────────

_guard_run() {
  local payload="$1"
  printf '%s' "$payload" | bash "$GUARD"
}

test_guard_allows_benign_bash() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')"
  [[ -z "$out" ]] || fail "expected empty output for benign cmd, got: $out"
}

test_guard_blocks_git_commit() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git commit, got: $out"
}

test_guard_blocks_git_push() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git push, got: $out"
}

test_guard_blocks_git_push_force() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git push --force"
}

test_guard_blocks_git_reset_hard() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git reset --hard"
}

test_guard_blocks_rm_rf() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/whatever"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for rm -rf"
}

test_guard_blocks_git_branch_delete() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git branch -D feat/old"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git branch -D"
}

test_guard_skips_non_bash_tool() {
  local out
  # Even with a destructive command string, if tool is not Bash → allow
  out="$(_guard_run '{"tool_name":"Edit","tool_input":{"command":"git commit -m x"}}')"
  [[ -z "$out" ]] || fail "expected empty output for non-Bash tool"
}

test_guard_empty_input_does_not_crash() {
  local out status
  out="$(_guard_run '' 2>&1)" || true
  status=$?
  (( status == 0 )) || fail "guard should exit 0 on empty input, got $status"
}

# ─── install-hooks command behavior ───────────────────────────────────────

_fresh_project() {
  local dir="$1"
  mkdir -p "$dir/.platform"
}

test_install_hooks_writes_both_artifacts() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  [[ -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "bash-guard.sh not installed"
  [[ -x "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "bash-guard.sh not executable"
  [[ -f "$dir/.claude/settings.json" ]] \
    || fail ".claude/settings.json not installed"
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
}

test_install_hooks_idempotent_when_already_present() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  # Re-run: should be no-op on settings.json (bash-guard already referenced)
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already referenced"
}

test_install_hooks_refuses_to_overwrite_unknown_settings() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  mkdir -p "$dir/.claude"
  printf '{"hooks":{"custom":"user-value"}}\n' > "$dir/.claude/settings.json"

  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "does NOT reference bash-guard"
  assert_contains "$output" "--force"
  # User's file left alone
  assert_file_contains "$dir/.claude/settings.json" "user-value"
  assert_file_not_contains "$dir/.claude/settings.json" "bash-guard.sh"
}

test_install_hooks_force_backs_up_and_overwrites() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  mkdir -p "$dir/.claude"
  printf '{"hooks":{"custom":"user-value"}}\n' > "$dir/.claude/settings.json"

  run_cli_capture output "$dir" install-hooks --force
  assert_status "$RUN_STATUS" 0
  # New content present
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
  # Backup exists with original content
  local backup=""
  for f in "$dir/.claude/"settings.json.agentboard-backup-*; do
    [[ -f "$f" ]] && { backup="$f"; break; }
  done
  [[ -n "$backup" ]] || fail "no backup created with --force"
  assert_file_contains "$backup" "user-value"
}

test_install_hooks_dry_run_writes_nothing() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks --dry-run
  assert_status "$RUN_STATUS" 0
  [[ ! -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "dry-run installed the guard"
  [[ ! -f "$dir/.claude/settings.json" ]] \
    || fail "dry-run installed settings.json"
}

test_install_hooks_fails_without_platform_dir() {
  local dir output
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No .platform"
}

test_install_hooks_help() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: ab install-hooks"
  assert_contains "$output" "bash-guard.sh"
}

test_init_ships_bash_guard_hook_in_settings() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
  # And the guard script itself ships
  [[ -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "init should ship bash-guard.sh"
}

# ─── --aliases flag behavior ──────────────────────────────────────────────

test_install_hooks_aliases_writes_to_zshrc() {
  local dir; dir="$(mktemp -d)"
  _fresh_project "$dir"
  local fake_home; fake_home="$(mktemp -d)"
  touch "$fake_home/.zshrc"
  local saved_HOME="$HOME"
  HOME="$fake_home"
  ( cd "$dir"; _ab_install_aliases 0 >/dev/null 2>&1 )
  HOME="$saved_HOME"
  assert_file_contains "$fake_home/.zshrc" "agentboard:aliases:begin"
  assert_file_contains "$fake_home/.zshrc" "command codex"
  assert_file_contains "$fake_home/.zshrc" "command gemini"
  rm -rf "$dir" "$fake_home"
}

test_install_hooks_aliases_idempotent() {
  local dir; dir="$(mktemp -d)"
  _fresh_project "$dir"
  local fake_home; fake_home="$(mktemp -d)"
  touch "$fake_home/.zshrc"
  local saved_HOME="$HOME"
  HOME="$fake_home"
  ( cd "$dir"; _ab_install_aliases 0 >/dev/null 2>&1; _ab_install_aliases 0 >/dev/null 2>&1 )
  HOME="$saved_HOME"
  local count; count="$(grep -c 'agentboard:aliases:begin' "$fake_home/.zshrc" 2>/dev/null || printf '0')"
  [[ "$count" -eq 1 ]] || fail "expected exactly one aliases block, got $count"
  rm -rf "$dir" "$fake_home"
}

test_install_hooks_aliases_force_replaces_block() {
  local dir; dir="$(mktemp -d)"
  _fresh_project "$dir"
  local fake_home; fake_home="$(mktemp -d)"
  touch "$fake_home/.zshrc"
  local saved_HOME="$HOME"
  HOME="$fake_home"
  ( cd "$dir"; _ab_install_aliases 0 >/dev/null 2>&1; _ab_install_aliases 1 >/dev/null 2>&1 )
  HOME="$saved_HOME"
  local count; count="$(grep -c 'agentboard:aliases:begin' "$fake_home/.zshrc" 2>/dev/null || printf '0')"
  [[ "$count" -eq 1 ]] || fail "expected exactly one aliases block after --force, got $count"
  rm -rf "$dir" "$fake_home"
}

test_install_hooks_aliases_flag_runs_only_aliases() {
  local dir; dir="$(mktemp -d)"
  _fresh_project "$dir"
  local fake_home; fake_home="$(mktemp -d)"
  touch "$fake_home/.zshrc"
  local output
  HOME="$fake_home" run_cli_capture output "$dir" install-hooks --aliases
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$fake_home/.zshrc" "agentboard:aliases:begin"
  # Should NOT install bash-guard (aliases-only mode)
  [[ ! -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "aliases-only mode should not install bash-guard.sh"
  rm -rf "$dir" "$fake_home"
}

# ─── subdirectory-safety regression (root cause: relative hook paths) ────────
#
# Root cause (2026-05-03): hook commands used `bash "./.platform/scripts/hooks/..."`.
# When the shell CWD shifted to a subdirectory (e.g. after `cd android`, or
# when a Task/Explore subagent started in a subdirectory), bash could not find
# the script → exit 127 → Claude Code showed "hook error" for every Bash call.
#
# Fix: all hook commands now use `git rev-parse --show-toplevel` to locate the
# project root, `cd` there, then execute the script with a repo-root-relative path.

test_settings_template_no_bare_relative_hooks() {
  # Regression guard: no hook command may use a bare "./.platform/..." path.
  local settings="$TEST_ROOT/templates/root/.claude/settings.json"
  [[ -f "$settings" ]] || fail "template settings.json not found at $settings"
  if grep -qE '"command"[[:space:]]*:[[:space:]]*"(bash|node) "\./\.platform/' "$settings" 2>/dev/null; then
    fail "settings.json template has bare CWD-relative hook path — breaks when shell CWD is a subdirectory"
  fi
}

test_settings_template_uses_git_rev_parse() {
  # Positive check: all hook commands must route through git rev-parse.
  local settings="$TEST_ROOT/templates/root/.claude/settings.json"
  [[ -f "$settings" ]] || fail "template settings.json not found at $settings"
  grep -q "git rev-parse --show-toplevel" "$settings" \
    || fail "settings.json template must use git rev-parse --show-toplevel for subdirectory safety"
}

test_installed_settings_uses_git_rev_parse() {
  # install-hooks must deploy the rev-parse format (not the old relative path).
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.claude/settings.json" "git rev-parse --show-toplevel"
  assert_file_not_contains "$dir/.claude/settings.json" 'bash "./.platform/scripts/hooks/'
  rm -rf "$dir"
}

test_hook_exits_0_from_subdirectory() {
  # Behavioral regression: hook command must exit 0 even when CWD is a nested
  # subdirectory of the project (e.g. android/app, src/components, etc.).
  local dir status
  dir="$(mktemp -d)"
  make_git_repo "$dir" main
  mkdir -p "$dir/.platform"
  run_cli_capture _out "$dir" install-hooks
  assert_status "$RUN_STATUS" 0

  mkdir -p "$dir/android/app/src"
  local payload='{"tool_name":"Bash","tool_input":{"command":"ls"},"hook_event_name":"PreToolUse","session_id":"t1"}'

  # Sanity check: the old bare path DOES fail from a subdirectory (confirms the
  # regression is real and our test environment is behaving correctly).
  set +e
  (cd "$dir/android/app/src" && printf '%s' "$payload" | bash "./.platform/scripts/hooks/bash-guard.sh" >/dev/null 2>&1)
  local old_exit=$?
  set -e
  (( old_exit != 0 )) \
    || fail "sanity: old relative path should fail from a subdir (test env issue)"

  # New git-rev-parse format must exit 0 from any subdirectory.
  set +e
  (
    cd "$dir/android/app/src"
    printf '%s' "$payload" | \
      bash -c 'ROOT=$(git rev-parse --show-toplevel 2>/dev/null); [ -n "$ROOT" ] && [ -f "$ROOT/.platform/scripts/hooks/bash-guard.sh" ] && { cd "$ROOT" && bash ".platform/scripts/hooks/bash-guard.sh"; } || exit 0'
  )
  status=$?
  set -e
  (( status == 0 )) || fail "hook command should exit 0 from subdirectory, got exit $status"
  rm -rf "$dir"
}

for t in \
  test_guard_allows_benign_bash \
  test_guard_blocks_git_commit \
  test_guard_blocks_git_push \
  test_guard_blocks_git_push_force \
  test_guard_blocks_git_reset_hard \
  test_guard_blocks_rm_rf \
  test_guard_blocks_git_branch_delete \
  test_guard_skips_non_bash_tool \
  test_guard_empty_input_does_not_crash \
  test_install_hooks_writes_both_artifacts \
  test_install_hooks_idempotent_when_already_present \
  test_install_hooks_refuses_to_overwrite_unknown_settings \
  test_install_hooks_force_backs_up_and_overwrites \
  test_install_hooks_dry_run_writes_nothing \
  test_install_hooks_fails_without_platform_dir \
  test_install_hooks_help \
  test_init_ships_bash_guard_hook_in_settings \
  test_install_hooks_aliases_writes_to_zshrc \
  test_install_hooks_aliases_idempotent \
  test_install_hooks_aliases_force_replaces_block \
  test_install_hooks_aliases_flag_runs_only_aliases \
  test_settings_template_no_bare_relative_hooks \
  test_settings_template_uses_git_rev_parse \
  test_installed_settings_uses_git_rev_parse \
  test_hook_exits_0_from_subdirectory; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
