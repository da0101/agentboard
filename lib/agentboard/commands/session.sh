cmd_sync() {
  local script="./.platform/scripts/sync-context.sh"
  [[ -x "$script" ]] || die "$script not found or not executable. Run 'agentboard init' first."
  "$script" "$@"
}

cmd_claim() {
  local active="./.platform/sessions/ACTIVE.md"
  [[ -f "$active" ]] || die "$active not found. This project may be single-repo (no ACTIVE.md needed)."
  local task="${1:-}"
  [[ -n "$task" ]] || die "Usage: agentboard claim \"<task summary>\""
  local agent="${AGENTBOARD_AGENT:-$USER@$(hostname -s)}"
  local ts; ts="$(date '+%Y-%m-%d %H:%M')"
  local repo; repo="$(basename "$(pwd)")"
  local row="| $ts | $agent | $repo | — | $task | ~30min | active |"
  printf '%s\n' "$row" >> "$active"
  ok "Claimed: $task"
}

cmd_release() {
  local active="./.platform/sessions/ACTIVE.md"
  [[ -f "$active" ]] || die "$active not found."
  local agent="${AGENTBOARD_AGENT:-$USER@$(hostname -s)}"
  local tmp; tmp="$(mktemp)"
  grep -v "| $agent |" "$active" > "$tmp" || true
  mv "$tmp" "$active"
  ok "Released all claims for $agent"
}

cmd_log() {
  local log="./.platform/log.md"
  [[ -f "$log" ]] || die "$log not found. Run 'agentboard init' first."
  local line="${1:-}"
  [[ -n "$line" ]] || die "Usage: agentboard log \"<one line summary>\""
  local today_str; today_str="$(today)"
  local tmp; tmp="$(mktemp)"
  awk -v new="${today_str} — ${line}" '
    /^---$/ && !inserted { print; print ""; print new; inserted=1; next }
    { print }
  ' "$log" > "$tmp"
  mv "$tmp" "$log"
  ok "Logged: $line"
}

cmd_status() {
  local status="./.platform/STATUS.md"
  [[ -f "$status" ]] || die "$status not found. Run 'agentboard init' first."
  cat "$status"
}

