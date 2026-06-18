# CI-mode helpers and local-environment checks for cmd_doctor.
# Bash dynamic scoping: ci_mode, _dr_pass, _dr_fail, warnings, errors
# are locals in cmd_doctor and visible here when called from within it.

_dr_ok() {
  _dr_pass=$(( _dr_pass + 1 ))
  if (( ci_mode )); then
    printf 'agentboard-doctor: PASS %s\n' "$*"
  else
    ok "$*"
  fi
}

_dr_warn() {
  _dr_fail=$(( _dr_fail + 1 ))
  if (( ci_mode )); then
    printf 'agentboard-doctor: FAIL %s\n' "$*"
  else
    warn "$*"
  fi
}

_dr_ci_check_sync() {
  local sync_script="$1"
  if [[ -x "$sync_script" ]]; then
    _dr_ok "sync-context.sh present and executable"
  else
    _dr_warn "sync-context.sh missing or not executable"
    warnings=$(( warnings + 1 ))
  fi
}

_dr_check_git_hooks() {
  [[ -d "./.git" ]] || return 0
  local hook hook_file
  for hook in pre-commit post-commit; do
    hook_file="./.git/hooks/$hook"
    if [[ -f "$hook_file" ]] && grep -q "ab" "$hook_file" 2>/dev/null; then
      ok "Git $hook hook installed"
    else
      warn "Git $hook hook not installed — run 'ab install-hooks'"
      warnings=$(( warnings + 1 ))
    fi
  done
  local post_commit="./.git/hooks/post-commit"
  if [[ -f "$post_commit" ]] && grep -q "ab checkpoint --auto" "$post_commit" 2>/dev/null; then
    ok "Auto-checkpoint wired into post-commit hook"
  else
    warn "Post-commit hook does not call 'ab checkpoint --auto' — auto-checkpoint disabled. Run 'ab update' to refresh hooks."
    warnings=$(( warnings + 1 ))
  fi
}

_dr_check_provider_wrappers() {
  local _w wp _cli _alias_found
  for _w in codex-ab gemini-ab; do
    wp="./.platform/scripts/$_w"
    if [[ -x "$wp" ]]; then
      ok "Provider wrapper $_w present and executable"
    elif [[ -f "$wp" ]]; then
      warn "Provider wrapper $wp exists but is not executable — run chmod +x"
      warnings=$(( warnings + 1 ))
    else
      warn "Provider wrapper $wp missing — run 'ab install-hooks'"
      warnings=$(( warnings + 1 ))
    fi
  done
  for _cli in codex gemini; do
    if command -v "$_cli" >/dev/null 2>&1; then
      _alias_found=0
      for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ -f "$rc" ]] && grep -q "agentboard:aliases" "$rc" 2>/dev/null && _alias_found=1
      done
      if (( _alias_found == 0 )); then
        warn "$_cli is in PATH but ab shell functions not installed — run 'ab install-hooks --aliases'"
        warnings=$(( warnings + 1 ))
      else
        ok "Shell function for $_cli installed"
      fi
    fi
  done
}

_dr_ci_summary() {
  printf 'agentboard-doctor: %d checks passed, %d failed\n' "$_dr_pass" "$_dr_fail"
  (( errors == 0 )) && return 0 || return 1
}
