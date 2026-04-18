# ---------------------------------------------------------------------------
# Shared helper — install the git pre-commit closure gate.
# Called from cmd_install_hooks and cmd_init.
# Args: project_dir [force=0] [dry_run=0]
# Returns 1 if an existing hook conflicts and --force was not passed.
# ---------------------------------------------------------------------------
_ab_install_git_closure_hook() {
  local project_dir="${1:-.}"
  local force="${2:-0}"
  local dry_run="${3:-0}"

  local hook_src="${project_dir}/.platform/scripts/hooks/pre-commit"
  local hook_dst="${project_dir}/.git/hooks/pre-commit"
  local marker="agentboard"

  # Not a git repo — nothing to wire
  [[ -d "${project_dir}/.git" ]] || return 0

  # Platform script not present — init hasn't run yet
  if [[ ! -f "$hook_src" ]]; then
    warn "pre-commit hook source missing at $hook_src — skipping git hook"
    return 0
  fi

  # Single-quoted heredoc keeps $? literal in the stub script
  local stub='#!/usr/bin/env bash
# agentboard — pre-commit closure gate
[[ -f ".platform/scripts/hooks/pre-commit" ]] && bash ".platform/scripts/hooks/pre-commit" || exit $?'

  if (( dry_run )); then
    if [[ ! -f "$hook_dst" ]]; then
      printf '  %s+%s would write %s  %s(new — git closure gate)%s\n' \
        "$C_CYAN" "$C_RESET" "$hook_dst" "$C_DIM" "$C_RESET"
    elif grep -q "$marker" "$hook_dst" 2>/dev/null; then
      printf '  %s↷%s %s  %s(agentboard git gate already present — no change)%s\n' \
        "$C_YELLOW" "$C_RESET" "$hook_dst" "$C_DIM" "$C_RESET"
    elif (( force )); then
      printf '  %s+%s would back up %s and overwrite\n' \
        "$C_CYAN" "$C_RESET" "$hook_dst"
    else
      printf '  %s!%s %s exists without agentboard — re-run with --force to overwrite\n' \
        "$C_YELLOW" "$C_RESET" "$hook_dst"
    fi
    return 0
  fi

  if [[ ! -f "$hook_dst" ]]; then
    mkdir -p "$(dirname "$hook_dst")"
    printf '%s' "$stub" > "$hook_dst"
    chmod +x "$hook_dst"
    printf '  %s✓%s %s  %s(new — git closure gate installed)%s\n' \
      "$C_GREEN" "$C_RESET" "$hook_dst" "$C_DIM" "$C_RESET"
  elif grep -q "$marker" "$hook_dst" 2>/dev/null; then
    printf '  %s↷%s %s  %s(agentboard git gate already present — no change)%s\n' \
      "$C_YELLOW" "$C_RESET" "$hook_dst" "$C_DIM" "$C_RESET"
  elif (( force )); then
    local ts; ts="$(date +%s)"
    local backup="${hook_dst}.agentboard-backup-${ts}"
    cp "$hook_dst" "$backup"
    printf '%s' "$stub" > "$hook_dst"
    chmod +x "$hook_dst"
    printf '  %s✓%s %s  %s(overwrote — backup at %s)%s\n' \
      "$C_GREEN" "$C_RESET" "$hook_dst" "$C_DIM" "$backup" "$C_RESET"
  else
    warn "$hook_dst exists and does NOT reference agentboard."
    say "  ${C_DIM}Two options:${C_RESET}"
    say "    1) Re-run with ${C_BOLD}--force${C_RESET} to back up and overwrite."
    say "    2) Append this to your existing pre-commit hook manually:"
    printf '\n'
    cat <<'SNIPPET'
      # agentboard closure gate
      [[ -f ".platform/scripts/hooks/pre-commit" ]] && \
        bash ".platform/scripts/hooks/pre-commit" || exit $?
SNIPPET
    printf '\n'
    return 1
  fi
}

cmd_install_hooks() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local force=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)   force=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) _install_hooks_print_help; return 0 ;;
      *) die "Unknown flag for install-hooks: $1" ;;
    esac
  done

  local guard_src="$TEMPLATES_PLATFORM/scripts/hooks/bash-guard.sh"
  local guard_dst="./.platform/scripts/hooks/bash-guard.sh"
  local settings_src="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_dst="./.claude/settings.json"
  local marker="bash-guard.sh"

  [[ -f "$guard_src" ]] || die "bash-guard.sh template missing at $guard_src"
  [[ -f "$settings_src" ]] || die "settings.json template missing at $settings_src"

  head "Agentboard hooks"

  # 1) Install the guard script (idempotent — template is source of truth)
  if (( dry_run )); then
    printf '  %s+%s would write %s\n' "$C_CYAN" "$C_RESET" "$guard_dst"
  else
    mkdir -p "$(dirname "$guard_dst")"
    cp "$guard_src" "$guard_dst"
    chmod +x "$guard_dst"
    printf '  %s✓%s %s  %s(executable)%s\n' \
      "$C_GREEN" "$C_RESET" "$guard_dst" "$C_DIM" "$C_RESET"
  fi

  # 2) Wire it into Claude Code settings.json
  if [[ ! -f "$settings_dst" ]]; then
    if (( dry_run )); then
      printf '  %s+%s would write %s (new)\n' "$C_CYAN" "$C_RESET" "$settings_dst"
    else
      mkdir -p "$(dirname "$settings_dst")"
      cp "$settings_src" "$settings_dst"
      printf '  %s✓%s %s  %s(new — closure-gate + bash-guard hooks installed)%s\n' \
        "$C_GREEN" "$C_RESET" "$settings_dst" "$C_DIM" "$C_RESET"
    fi
  elif grep -q "$marker" "$settings_dst"; then
    printf '  %s↷%s %s  %s(bash-guard already referenced — no change)%s\n' \
      "$C_YELLOW" "$C_RESET" "$settings_dst" "$C_DIM" "$C_RESET"
  else
    # Existing settings without the guard. Safest thing is to back up + overwrite
    # when --force. Otherwise refuse and print a snippet for manual install.
    if (( force )); then
      local ts; ts="$(date +%s)"
      local backup="${settings_dst}.agentboard-backup-${ts}"
      if (( dry_run )); then
        printf '  %s+%s would back up existing to %s and overwrite with template\n' \
          "$C_CYAN" "$C_RESET" "$backup"
      else
        cp "$settings_dst" "$backup"
        cp "$settings_src" "$settings_dst"
        printf '  %s✓%s %s  %s(overwrote — backup saved to %s)%s\n' \
          "$C_GREEN" "$C_RESET" "$settings_dst" "$C_DIM" "$backup" "$C_RESET"
      fi
    else
      warn "$settings_dst exists and does NOT reference bash-guard.sh."
      say "  ${C_DIM}Two options:${C_RESET}"
      say "    1) Re-run with ${C_BOLD}--force${C_RESET} to back up the existing file and overwrite."
      say "    2) Add this hook entry under ${C_BOLD}hooks.PreToolUse${C_RESET} manually:"
      printf '\n'
      cat <<'JSON'
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"./.platform/scripts/hooks/bash-guard.sh\"",
            "timeout": 5
          }
        ]
      }
JSON
      printf '\n'
      return 1
    fi
  fi

  # 3) Git pre-commit closure gate (provider-agnostic)
  _ab_install_git_closure_hook "." "$force" "$dry_run" || true

  if (( dry_run )); then
    say "${C_DIM}Dry run. Re-run without --dry-run to apply.${C_RESET}"
    return 0
  fi

  ok "Hooks installed."
  say "  ${C_DIM}Claude Code: approval prompt fires on git commit / push / reset --hard / rm -rf.${C_RESET}"
  say "  ${C_DIM}All providers: git pre-commit blocks stream closure without human sign-off.${C_RESET}"
}

_install_hooks_print_help() {
  cat <<'EOF'
Usage: agentboard install-hooks [--force] [--dry-run]

Installs the Claude Code hook system that gates destructive shell commands
and enforces stream-closure approval.

What gets installed:
  .platform/scripts/hooks/bash-guard.sh
      PreToolUse hook on the Bash tool. Intercepts `git commit`, `git push`,
      `git reset --hard`, `git checkout --`, `git branch -D`, `rm -rf` and
      returns `permissionDecision: ask` — you click yes/no in Claude Code.
      LLMs cannot bypass. Claude Code only.

  .claude/settings.json
      Wires the guard into Claude Code. Also installs the existing
      closure-gate and session-bootstrap hooks shipped with agentboard init.

  .git/hooks/pre-commit
      Provider-agnostic closure gate. Fires before every commit regardless
      of which AI tool (Claude, Codex, Gemini) made the edit. Blocks
      committing an ACTIVE.md change that removes a stream row unless the
      stream file has closure_approved: true. Fail-open: unexpected errors
      allow the commit through. Bypass (emergency): git commit --no-verify.

Flags:
  --force     Overwrite existing .claude/settings.json and/or
              .git/hooks/pre-commit (backups saved with .agentboard-backup-<ts>
              suffix). Without --force, conflicting files are left alone and
              a snippet is printed for manual install.
  --dry-run   Print what would change without writing anything.

Notes:
  - Fresh `agentboard init` already installs all three. This command is
    for existing projects, re-install, or upgrading the git hook.
  - The bash-guard is deliberately fail-open: if the hook errors, commands
    still run. Worst case: one extra click. Never blocks your work.
EOF
}
