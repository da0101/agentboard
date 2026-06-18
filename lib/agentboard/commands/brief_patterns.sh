# Platform value loop — `ab brief` patterns & suggestions section
# Called at the end of cmd_brief(). Silently exits when sqlite3 / DB absent.

_brief_patterns() {
  local db="${AGENTBOARD_USAGE_DB:-$HOME/.agentboard/usage.db}"
  command -v sqlite3 >/dev/null 2>&1 || return 0
  [[ -f "$db" ]] || return 0

  local count
  count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage;" 2>/dev/null || echo 0)"
  [[ -z "$count" || "$count" -lt 5 ]] && return 0

  local cutoff
  cutoff="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || true)"

  # Top 3 skills by use count (note starts with "skill:")
  local skills_out top_skill skill_count
  skills_out="$(sqlite3 "$db" \
    "SELECT REPLACE(note,'skill:',''), COUNT(*) as c FROM usage
     WHERE note LIKE 'skill:%' AND logged_at >= '${cutoff}'
     GROUP BY note ORDER BY c DESC LIMIT 3;" 2>/dev/null || true)"

  # Top task_type by total tokens (last 30 days)
  local top_type
  top_type="$(sqlite3 "$db" \
    "SELECT task_type FROM usage WHERE task_type != '' AND logged_at >= '${cutoff}'
     GROUP BY task_type ORDER BY SUM(total_tokens) DESC LIMIT 1;" 2>/dev/null || true)"

  # Stream with highest token cost (last 30 days)
  local top_stream top_stream_tokens
  top_stream="$(sqlite3 "$db" \
    "SELECT stream_slug FROM usage WHERE stream_slug != '' AND logged_at >= '${cutoff}'
     GROUP BY stream_slug ORDER BY SUM(total_tokens) DESC LIMIT 1;" 2>/dev/null || true)"
  top_stream_tokens="$(sqlite3 "$db" \
    "SELECT SUM(total_tokens) FROM usage WHERE stream_slug='${top_stream//\'/\'\'}' AND logged_at >= '${cutoff}';" \
    2>/dev/null || true)"

  # Debug frequency check
  local debug_count
  debug_count="$(sqlite3 "$db" \
    "SELECT COUNT(*) FROM usage WHERE lower(COALESCE(task_type,'')) = 'debug' AND logged_at >= '${cutoff}';" \
    2>/dev/null || echo 0)"

  # Skill session frequency: skill used in every distinct calendar day
  local skill_days total_days dominant_skill=""
  if [[ -n "$skills_out" ]]; then
    top_skill="$(printf '%s\n' "$skills_out" | head -1 | cut -d'|' -f1)"
    skill_days="$(sqlite3 "$db" \
      "SELECT COUNT(DISTINCT date(logged_at)) FROM usage WHERE note='skill:${top_skill//\'/\'\'}' AND logged_at >= '${cutoff}';" \
      2>/dev/null || echo 0)"
    total_days="$(sqlite3 "$db" \
      "SELECT COUNT(DISTINCT date(logged_at)) FROM usage WHERE logged_at >= '${cutoff}';" \
      2>/dev/null || echo 0)"
    if [[ -n "$skill_days" && -n "$total_days" && "$total_days" -gt 0 ]]; then
      [[ "$skill_days" -ge "$total_days" ]] && dominant_skill="$top_skill"
    fi
  fi

  # Collect actionable lines
  local -a lines=()
  [[ -n "$top_type" ]] && \
    lines+=("   Top task type (tokens): ${C_BOLD}${top_type}${C_RESET}")
  [[ -n "$top_stream" && -n "$top_stream_tokens" ]] && \
    lines+=("   Costliest stream: ${C_BOLD}${top_stream}${C_RESET} (${top_stream_tokens} tokens, 30d)")
  if [[ -n "$skills_out" ]]; then
    local s_line="   Top skills: "
    while IFS='|' read -r sname scnt; do
      [[ -z "$sname" ]] && continue
      s_line="${s_line}${sname}(${scnt}) "
    done <<< "$skills_out"
    lines+=("$s_line")
  fi
  [[ "$debug_count" -gt 10 ]] && \
    lines+=("   ${C_YELLOW}⚠  debug tasks: ${debug_count} in 30d — consider /ab-debug for systematic root-cause${C_RESET}")
  [[ -n "$dominant_skill" ]] && \
    lines+=("   ${C_DIM}Tip: '${dominant_skill}' used daily — add to activation defaults${C_RESET}")

  (( ${#lines[@]} == 0 )) && return 0

  printf '%s📊 Patterns & Suggestions%s\n' "$C_BOLD" "$C_RESET"
  local ln
  for ln in "${lines[@]}"; do printf '%s\n' "$ln"; done
  printf '\n'
}
