# `ab watch --uninstall` / `ab watch --status` — scheduler removal and
# install/active/log-state reporting.

_watch_uninstall() {
  local sched; sched="$(_watch_scheduler)"
  [[ "$sched" != "unsupported" ]] || die "--uninstall is only supported on macOS and Linux."

  local slug; slug="$(_watch_project_slug)"

  if [[ "$sched" == "launchd" ]]; then
    local label="com.agentboard.${slug}"
    local plist="$(_watch_home)/Library/LaunchAgents/${label}.plist"
    local launchd_target
    launchd_target="$(_watch_launchd_target "$label")"
    local removed=0
    if launchctl bootout "$launchd_target" 2>/dev/null; then removed=1; fi
    launchctl unload "$plist" 2>/dev/null || true
    if [[ -f "$plist" ]]; then
      rm -f "$plist"
      removed=1
    fi
    if (( removed )); then
      _watch_rmdir_if_empty "$(_watch_home)/Library/LaunchAgents"
      _watch_rmdir_if_empty "$(_watch_home)/Library"
      _watch_rmdir_if_empty "$(_watch_home)/.ab"
      ok "Uninstalled launchd agent ${C_BOLD}${label}${C_RESET}"
    else
      say "${C_DIM}No launchd agent found for this project (slug=${slug}).${C_RESET}"
    fi
  else
    local unit="agentboard-${slug}"
    local service="$(_watch_home)/.config/systemd/user/${unit}.service"
    local timer="$(_watch_home)/.config/systemd/user/${unit}.timer"
    local removed=0
    systemctl --user disable --now "${unit}.timer" 2>/dev/null && removed=1 || true
    if [[ -f "$service" || -f "$timer" ]]; then
      rm -f "$service" "$timer"
      systemctl --user daemon-reload 2>/dev/null || true
      removed=1
    fi
    if (( removed )); then
      _watch_rmdir_if_empty "$(_watch_home)/.config/systemd/user"
      _watch_rmdir_if_empty "$(_watch_home)/.config/systemd"
      _watch_rmdir_if_empty "$(_watch_home)/.config"
      _watch_rmdir_if_empty "$(_watch_home)/.ab"
      ok "Uninstalled systemd timer ${C_BOLD}${unit}.timer${C_RESET}"
    else
      say "${C_DIM}No systemd units found for this project (slug=${slug}).${C_RESET}"
    fi
  fi
}

_watch_status() {
  local sched; sched="$(_watch_scheduler)"
  [[ "$sched" != "unsupported" ]] || die "--status is only supported on macOS and Linux."

  local slug; slug="$(_watch_project_slug)"
  local log_file; log_file="$(_watch_log_path "$slug")"

  printf '%sAgentboard watch status%s  (slug=%s, scheduler=%s)\n' \
    "$C_BOLD" "$C_RESET" "$slug" "$sched"

  if [[ "$sched" == "launchd" ]]; then
    local label="com.agentboard.${slug}"
    local plist="$(_watch_home)/Library/LaunchAgents/${label}.plist"
    local loaded=0
    if launchctl print "$(_watch_launchd_target "$label")" >/dev/null 2>&1; then
      loaded=1
    fi
    if [[ -f "$plist" ]]; then
      printf '  %sInstalled:%s yes (%s)\n' "$C_DIM" "$C_RESET" "$plist"
      if (( loaded )); then
        printf '  %sLoaded:%s yes\n' "$C_DIM" "$C_RESET"
      else
        printf '  %sLoaded:%s no — try: launchctl bootstrap gui/$(id -u) %s\n' \
          "$C_DIM" "$C_RESET" "$plist"
      fi
    elif (( loaded )); then
      printf '  %sInstalled:%s no — but service is still loaded (orphan). Run: launchctl bootout gui/$(id -u)/%s\n' \
        "$C_DIM" "$C_RESET" "$label"
    else
      printf '  %sInstalled:%s no — run: ab watch --install\n' "$C_DIM" "$C_RESET"
    fi
  else
    local unit="agentboard-${slug}"
    local service="$(_watch_home)/.config/systemd/user/${unit}.service"
    local timer="$(_watch_home)/.config/systemd/user/${unit}.timer"
    local installed_path=""
    local active=0
    if systemctl --user is-active "${unit}.timer" >/dev/null 2>&1; then
      active=1
    fi
    if [[ -f "$timer" ]]; then
      installed_path="$timer"
    elif [[ -f "$service" ]]; then
      installed_path="$service"
    fi
    if [[ -n "$installed_path" ]]; then
      printf '  %sInstalled:%s yes (%s)\n' "$C_DIM" "$C_RESET" "$installed_path"
      if (( active )); then
        printf '  %sActive:%s yes\n' "$C_DIM" "$C_RESET"
      else
        printf '  %sActive:%s no — try: systemctl --user enable --now %s.timer\n' \
          "$C_DIM" "$C_RESET" "$unit"
      fi
    elif (( active )); then
      printf '  %sInstalled:%s no — but service is still loaded (orphan). Run: systemctl --user disable --now %s.timer\n' \
        "$C_DIM" "$C_RESET" "$unit"
    else
      printf '  %sInstalled:%s no — run: ab watch --install\n' "$C_DIM" "$C_RESET"
    fi
  fi

  if [[ -f "$log_file" ]]; then
    local size last
    if [[ "$(uname)" == "Darwin" ]]; then
      size="$(stat -f %z "$log_file" 2>/dev/null || echo 0)"
      last="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$log_file" 2>/dev/null || echo '-')"
    else
      size="$(stat -c %s "$log_file" 2>/dev/null || echo 0)"
      last="$(stat -c '%y' "$log_file" 2>/dev/null | cut -d. -f1 || echo '-')"
    fi
    printf '  %sLog:%s %s  (%s bytes, last-modified %s)\n' \
      "$C_DIM" "$C_RESET" "$log_file" "$size" "$last"
  else
    printf '  %sLog:%s (no entries yet — poll has not fired)\n' "$C_DIM" "$C_RESET"
  fi
}
