cmd_sync() {
  local script=".platform/scripts/sync-context.sh"

  [[ -d ".platform" ]] || die "No .platform/ found. Run 'ab init' from this repo before using ab sync."
  [[ -f "$script" ]] || die "$script is missing. Run 'ab update' from this repo to restore shipped scripts, then run 'ab sync' again."
  [[ -x "$script" ]] || die "$script is not executable. Run 'ab update' from this repo to restore permissions, then run 'ab sync' again."

  "$script" "$@"
}

cmd_status() {
  local status="./.platform/STATUS.md"
  [[ -f "$status" ]] || die "$status not found. Run 'ab init' first."
  cat "$status"
}
