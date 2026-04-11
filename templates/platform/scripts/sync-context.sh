#!/usr/bin/env bash
# sync-context.sh — keep AGENTS.md and GEMINI.md in lockstep with CLAUDE.md
#
# CLAUDE.md is the single source of truth. AGENTS.md (Codex CLI) and GEMINI.md
# (Gemini CLI) are generated from it by two sed substitutions per variant.
#
# Modes:
#   sync-context.sh           Default: check. Prints OK / DRIFT, exits non-zero on drift.
#   sync-context.sh --apply   Regenerate drifted files.
#   sync-context.sh --list    List the repos configured for sync.
#   sync-context.sh --help    Usage.

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration — EDIT THIS for your project
# -----------------------------------------------------------------------------
#
# REPOS is a list of absolute paths to every repo whose CLAUDE.md / AGENTS.md /
# GEMINI.md should stay in sync. Include the platform repo itself as the first
# entry. For single-repo projects, just list one path.
#
# Example:
#   REPOS=(
#     "$HOME/code/my-project"
#     "$HOME/code/my-project-backend"
#     "$HOME/code/my-project-frontend"
#   )

REPOS=(
  # Add your repo paths here
  "."
)

# -----------------------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------------------

MODE="check"
case "${1:-}" in
  --apply) MODE="apply" ;;
  --list)
    printf 'Configured repos:\n'
    for r in "${REPOS[@]}"; do printf '  %s\n' "$r"; done
    exit 0
    ;;
  --help|-h)
    sed -n '2,12p' "$0"
    exit 0
    ;;
  "") ;;
  *) printf 'Unknown flag: %s\n' "$1" >&2; exit 2 ;;
esac

# Generate AGENTS.md variant from CLAUDE.md
generate_agents() {
  local src="$1"
  sed -e 's/Claude Code/Codex CLI/g' \
      -e 's|CLAUDE\.md|AGENTS.md|g' \
      < "$src"
}

# Generate GEMINI.md variant from CLAUDE.md
generate_gemini() {
  local src="$1"
  sed -e 's/Claude Code/Gemini CLI/g' \
      -e 's|CLAUDE\.md|GEMINI.md|g' \
      < "$src"
}

DRIFT=0

for repo in "${REPOS[@]}"; do
  claude_md="$repo/CLAUDE.md"
  agents_md="$repo/AGENTS.md"
  gemini_md="$repo/GEMINI.md"

  if [[ ! -f "$claude_md" ]]; then
    printf 'SKIP   %s (no CLAUDE.md)\n' "$repo"
    continue
  fi

  # AGENTS.md
  expected_agents="$(generate_agents "$claude_md")"
  if [[ -f "$agents_md" ]] && diff -q <(printf '%s\n' "$expected_agents") "$agents_md" >/dev/null 2>&1; then
    printf 'OK     %s/AGENTS.md\n' "$(basename "$repo")"
  else
    if [[ "$MODE" == "apply" ]]; then
      printf '%s\n' "$expected_agents" > "$agents_md"
      printf 'WROTE  %s/AGENTS.md\n' "$(basename "$repo")"
    else
      printf 'DRIFT  %s/AGENTS.md\n' "$(basename "$repo")"
      DRIFT=1
    fi
  fi

  # GEMINI.md
  expected_gemini="$(generate_gemini "$claude_md")"
  if [[ -f "$gemini_md" ]] && diff -q <(printf '%s\n' "$expected_gemini") "$gemini_md" >/dev/null 2>&1; then
    printf 'OK     %s/GEMINI.md\n' "$(basename "$repo")"
  else
    if [[ "$MODE" == "apply" ]]; then
      printf '%s\n' "$expected_gemini" > "$gemini_md"
      printf 'WROTE  %s/GEMINI.md\n' "$(basename "$repo")"
    else
      printf 'DRIFT  %s/GEMINI.md\n' "$(basename "$repo")"
      DRIFT=1
    fi
  fi
done

if [[ "$MODE" == "check" && "$DRIFT" -eq 1 ]]; then
  printf '\nOne or more entry files drifted. Run: sync-context.sh --apply\n' >&2
  exit 1
fi

printf '\nAll entry files in sync.\n'
