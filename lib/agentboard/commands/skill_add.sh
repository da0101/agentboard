cmd_skill_add() {
  local source="${1:-}"
  if [[ -z "$source" ]]; then
    die "Usage: ab skill add <url-or-path>"
  fi

  local tmp_file="/tmp/agentboard-skill-$$.md"
  local is_url=0

  # Determine source type
  if [[ "$source" == http://* ]] || [[ "$source" == https://* ]]; then
    is_url=1
  fi

  # Fetch or copy the skill file
  if [[ "$is_url" -eq 1 ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      die "curl is required to install skills from URLs but was not found in PATH."
    fi
    say "  Downloading skill from ${C_BOLD}${source}${C_RESET} …"
    if ! curl -fsSL "$source" -o "$tmp_file" 2>/dev/null; then
      rm -f "$tmp_file"
      die "Download failed. Check that the URL is reachable and returns a valid SKILL.md file."
    fi
  else
    if [[ ! -f "$source" ]]; then
      die "Local path not found: $source"
    fi
    cp "$source" "$tmp_file"
  fi

  # Extract the name field from YAML frontmatter
  local skill_name
  skill_name="$(grep -m1 '^name:' "$tmp_file" | sed 's/^name:[[:space:]]*//' | tr -d '[:space:]"' | tr -d "'")" || true

  if [[ -z "$skill_name" ]]; then
    rm -f "$tmp_file"
    die "Could not find a 'name:' field in the YAML frontmatter of the skill file. Ensure the file starts with ---\\nname: <skill-name>\\n..."
  fi

  say "  Skill name: ${C_BOLD}${skill_name}${C_RESET}"

  # Install locations
  local -a written_locations=()

  # 1. Install to templates/skills/<name>/SKILL.md (the agentboard source of truth)
  if [[ -n "${AGENTBOARD_ROOT:-}" ]] && [[ -d "$AGENTBOARD_ROOT/templates/skills" ]]; then
    local templates_dest="$AGENTBOARD_ROOT/templates/skills/$skill_name"
    mkdir -p "$templates_dest"
    cp "$tmp_file" "$templates_dest/SKILL.md"
    written_locations+=("$templates_dest/SKILL.md")
  fi

  # 2. Install to .claude/skills/<name>/SKILL.md if harness directory exists
  if [[ -d ".claude/skills" ]]; then
    local claude_dest=".claude/skills/$skill_name"
    mkdir -p "$claude_dest"
    cp "$tmp_file" "$claude_dest/SKILL.md"
    written_locations+=("$claude_dest/SKILL.md")
  fi

  # Cleanup temp file
  rm -f "$tmp_file"

  if [[ ${#written_locations[@]} -eq 0 ]]; then
    die "No install locations found. Expected \$AGENTBOARD_ROOT/templates/skills/ or .claude/skills/ in the current directory."
  fi

  # Propagate to all harness directories
  say "  Running sync-skills to propagate to all harness directories …"
  cmd_sync_skills

  ok "Installed skill: ${skill_name}"
  local loc
  for loc in "${written_locations[@]}"; do
    say "    ${C_DIM}→ ${loc}${C_RESET}"
  done
}

cmd_skill() {
  local sub="${1:-}"
  shift 2>/dev/null || true
  case "$sub" in
    add) cmd_skill_add "$@" ;;
    *)   die "Usage: ab skill add <url-or-path>" ;;
  esac
}
