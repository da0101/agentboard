# ---------------------------------------------------------------------------
# Shared helper — install a delegating git hook stub.
# Called from cmd_install_hooks and cmd_init.
# Args: hook_name platform_script project_dir [force=0] [dry_run=0]
#   hook_name:       pre-commit | post-commit | …
#   platform_script: relative path from project root to the platform script
#   project_dir:     project root (default: .)
# Returns 1 if an existing hook conflicts and --force was not passed.
# ---------------------------------------------------------------------------
_ab_install_git_hook() {
  local hook_name="$1"
  local platform_script="$2"
  local project_dir="${3:-.}"
  local force="${4:-0}"
  local dry_run="${5:-0}"

  local hook_src="${project_dir}/${platform_script}"
  local hook_dst="${project_dir}/.git/hooks/${hook_name}"
  local marker="agentboard"

  [[ -d "${project_dir}/.git" ]] || return 0

  if [[ ! -f "$hook_src" ]]; then
    warn "$hook_name source missing at $hook_src — skipping"
    return 0
  fi

  # Stub delegates to the platform script (kept in .platform/, git-trackable).
  # Single-quoted string keeps $? literal in the written file.
  local stub='#!/usr/bin/env bash
# agentboard — '"$hook_name"'
[[ -f "'"$platform_script"'" ]] && bash "'"$platform_script"'" || exit $?'

  if (( dry_run )); then
    if [[ ! -f "$hook_dst" ]]; then
      printf '  %s+%s would write %s  %s(new — %s)%s\n' \
        "$C_CYAN" "$C_RESET" "$hook_dst" "$C_DIM" "$hook_name" "$C_RESET"
    elif grep -q "$marker" "$hook_dst" 2>/dev/null; then
      printf '  %s↷%s %s  %s(agentboard %s already present — no change)%s\n' \
        "$C_YELLOW" "$C_RESET" "$hook_dst" "$C_DIM" "$hook_name" "$C_RESET"
    elif (( force )); then
      printf '  %s+%s would back up %s and overwrite\n' "$C_CYAN" "$C_RESET" "$hook_dst"
    else
      printf '  %s!%s %s exists without agentboard — re-run with --force to overwrite\n' \
        "$C_YELLOW" "$C_RESET" "$hook_dst"
    fi
    return 0
  fi

  if [[ ! -f "$hook_dst" ]]; then
    mkdir -p "$(dirname "$hook_dst")"
    printf '%s\n' "$stub" > "$hook_dst"
    chmod +x "$hook_dst"
    printf '  %s✓%s %s  %s(new — %s installed)%s\n' \
      "$C_GREEN" "$C_RESET" "$hook_dst" "$C_DIM" "$hook_name" "$C_RESET"
  elif grep -q "$marker" "$hook_dst" 2>/dev/null; then
    printf '  %s↷%s %s  %s(agentboard %s already present — no change)%s\n' \
      "$C_YELLOW" "$C_RESET" "$hook_dst" "$C_DIM" "$hook_name" "$C_RESET"
  elif (( force )); then
    local ts; ts="$(date +%s)"
    local backup="${hook_dst}.agentboard-backup-${ts}"
    cp "$hook_dst" "$backup"
    printf '%s\n' "$stub" > "$hook_dst"
    chmod +x "$hook_dst"
    printf '  %s✓%s %s  %s(overwrote — backup at %s)%s\n' \
      "$C_GREEN" "$C_RESET" "$hook_dst" "$C_DIM" "$backup" "$C_RESET"
  else
    warn "$hook_dst exists and does NOT reference agentboard."
    say "  ${C_DIM}Options: --force to overwrite, or append manually:${C_RESET}"
    printf '\n'
    printf '      # agentboard %s\n' "$hook_name"
    printf '      [[ -f "%s" ]] && bash "%s" || exit $?\n' \
      "$platform_script" "$platform_script"
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

  # 3) Git pre-commit closure gate (provider-agnostic — blocks unapproved stream closure)
  _ab_install_git_hook "pre-commit" \
    ".platform/scripts/hooks/pre-commit" "." "$force" "$dry_run" || true

  # 4) Git post-commit activity log (auto-breadcrumbs for Codex/Gemini sessions)
  _ab_install_git_hook "post-commit" \
    ".platform/scripts/hooks/post-commit" "." "$force" "$dry_run" || true

  # 5) Provider wrappers — print alias instructions (don't auto-modify shell config)
  if ! (( dry_run )); then
    local wrappers_dir="./.platform/scripts"
    local did_wrappers=0
    for w in codex-ab gemini-ab; do
      local wp="${wrappers_dir}/${w}"
      if [[ -f "$wp" ]]; then
        chmod +x "$wp"
        did_wrappers=1
      fi
    done
    if (( did_wrappers )); then
      printf '  %s✓%s %s  %s(provider wrappers — see alias tip below)%s\n' \
        "$C_GREEN" "$C_RESET" "$wrappers_dir/{codex-ab,gemini-ab}" "$C_DIM" "$C_RESET"
    fi
  fi

  if (( dry_run )); then
    say "${C_DIM}Dry run. Re-run without --dry-run to apply.${C_RESET}"
    return 0
  fi

  ok "Hooks installed."
  say "  ${C_DIM}Claude Code: approval prompt fires on git commit / push / reset --hard / rm -rf.${C_RESET}"
  say "  ${C_DIM}All providers: pre-commit blocks unapproved stream closure; post-commit logs to memory/log.md.${C_RESET}"
  say
  say "  ${C_BOLD}Codex / Gemini session bootstrap alias${C_RESET} — add to your shell for full parity:"
  printf '    alias codex=%s"bash \"%s/.platform/scripts/codex-ab\""%s\n' \
    "$C_CYAN" '$(git rev-parse --show-toplevel 2>/dev/null || pwd)' "$C_RESET"
  printf '    alias gemini=%s"bash \"%s/.platform/scripts/gemini-ab\""%s\n' \
    "$C_CYAN" '$(git rev-parse --show-toplevel 2>/dev/null || pwd)' "$C_RESET"
  say "  ${C_DIM}These wrappers run \`agentboard brief\` before each session — same as Claude Code's session hook.${C_RESET}"
}

_install_hooks_print_help() {
  cat <<'EOF'
Usage: agentboard install-hooks [--force] [--dry-run]

Installs the full agentboard hook stack for all providers.

What gets installed:
  .platform/scripts/hooks/bash-guard.sh         [Claude Code only]
      PreToolUse hook — intercepts destructive Bash commands (git commit,
      git push, git reset --hard, rm -rf) and asks for approval.

  .claude/settings.json                          [Claude Code only]
      Wires bash-guard + closure gate + session bootstrap into Claude Code.

  .git/hooks/pre-commit                          [all providers]
      Blocks committing an ACTIVE.md change that removes a stream row
      unless closure_approved: true. Fail-open. Bypass: --no-verify.

  .git/hooks/post-commit                         [all providers]
      Appends one line to .platform/memory/log.md after every commit.
      Auto-breadcrumbs for Codex/Gemini sessions that miss checkpoints.

  .platform/scripts/codex-ab                     [Codex CLI]
  .platform/scripts/gemini-ab                    [Gemini CLI]
      Provider wrappers — run `agentboard brief` before launch so agents
      start every session with full project context. Use as aliases:
        alias codex="bash .platform/scripts/codex-ab"
        alias gemini="bash .platform/scripts/gemini-ab"

Flags:
  --force     Overwrite existing .claude/settings.json and/or git hooks
              (backups saved with .agentboard-backup-<ts> suffix).
  --dry-run   Print what would change without writing anything.

Notes:
  - Fresh `agentboard init` already installs everything. This command is
    for existing projects, re-install, or upgrading hooks after agentboard update.
  - All hooks are fail-open: errors allow through rather than block.
EOF
}
