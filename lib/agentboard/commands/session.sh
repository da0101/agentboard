cmd_sync() {
  local script="./.platform/scripts/sync-context.sh"
  [[ -x "$script" ]] || die "$script not found or not executable. Run 'agentboard init' first."
  "$script" "$@"
}

cmd_status() {
  local status="./.platform/STATUS.md"
  [[ -f "$status" ]] || die "$status not found. Run 'agentboard init' first."
  cat "$status"
}
