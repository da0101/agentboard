# delegate.sh — queue a specialist role for VS Code to open in a new terminal
# Usage: agentboard delegate <role-slug> "<task>"
#
# Writes ~/.agentboard/delegate.json, which the VS Code extension detects on its
# next poll tick and opens a new terminal running:
#   claude "Adopt the <role>. Context: <...>. Your task: <task>"

cmd_delegate() {
  local role_slug="${1:-}"
  local task="${2:-}"

  if [[ -z "$role_slug" || -z "$task" ]]; then
    die "Usage: agentboard delegate <role-slug> \"<task description>\""
  fi

  # Resolve project root
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="$PWD"
  local project_name
  project_name="$(basename "$root")"

  # Current git branch
  local branch
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="unknown"

  # Build context: What are we building + Current state from BRIEF.md
  local context=""
  local brief="$root/.platform/work/BRIEF.md"
  if [[ -f "$brief" ]]; then
    local what_building current_state
    what_building="$(markdown_section_excerpt "$brief" "## What we're building" 2>/dev/null)" || what_building=""
    current_state="$(markdown_section_excerpt "$brief" "## Current state" 2>/dev/null)" || current_state=""
    [[ -n "$what_building" ]] && context="$what_building"
    if [[ -n "$current_state" ]]; then
      [[ -n "$context" ]] && context="$context

Current state: $current_state" || context="$current_state"
    fi
  fi

  # Fall back to the stream objective if BRIEF is empty
  if [[ -z "$context" ]]; then
    local active="$root/.platform/work/ACTIVE.md"
    if [[ -f "$active" ]]; then
      context="$(grep -m1 'objective:' "$active" | sed 's/.*objective: *//' | tr -d '"' 2>/dev/null)" || context=""
    fi
  fi

  # Write JSON via Python3 so arbitrary text is correctly escaped
  local delegate_dir="$HOME/.agentboard"
  mkdir -p "$delegate_dir"

  ROLE="$role_slug" \
  TASK="$task" \
  CONTEXT="$context" \
  BRANCH="$branch" \
  ROOT="$root" \
  PROJECT="$project_name" \
  python3 -c "
import json, os, datetime
print(json.dumps({
  'role':    os.environ['ROLE'],
  'task':    os.environ['TASK'],
  'context': os.environ['CONTEXT'],
  'branch':  os.environ['BRANCH'],
  'root':    os.environ['ROOT'],
  'project': os.environ['PROJECT'],
  'ts':      datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
}))
" > "$delegate_dir/delegate.json"

  ok "Delegation queued → ${role_slug}: ${task}"
  printf '  %sVS Code will open a new terminal with Claude as %s%s%s%s.\n' \
    "$C_DIM" "$C_RESET" "$C_BOLD" "$role_slug" "$C_RESET"
}
