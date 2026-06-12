# `ab watch --install` — per-project scheduler installation
# (launchd on macOS, systemd user timer on Linux).

# Detect the scheduler the current OS uses to run the per-10-min poll.
# macOS → launchd; Linux → systemd user timer. Other OSes are not supported
# (Windows/WSL need a different story; see the stream decision log).
_watch_scheduler() {
  case "$(uname)" in
    Darwin) printf 'launchd\n' ;;
    Linux)  printf 'systemd\n' ;;
    *)      printf 'unsupported\n' ;;
  esac
}

# Kebab-case slug derived from the project directory name. Used as a unique
# per-project label for the launchd/systemd unit so multiple ab
# projects can coexist on one machine without colliding.
_watch_project_slug() {
  local name
  name="$(basename "$(pwd)")"
  # Lowercase, replace runs of non-alphanum with -, trim leading/trailing -
  printf '%s' "$name" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Resolve the absolute path to the ab binary so scheduled jobs don't
# depend on PATH. Walks up from the sourced script location.
_watch_ab_bin() {
  local bin
  if [[ -n "${AGENTBOARD_ROOT:-}" && -x "$AGENTBOARD_ROOT/bin/ab" ]]; then
    bin="$AGENTBOARD_ROOT/bin/ab"
  elif command -v ab >/dev/null 2>&1; then
    bin="$(command -v ab)"
  else
    die "Cannot resolve absolute path to ab binary"
  fi
  printf '%s' "$bin"
}

_watch_home() {
  printf '%s' "${AGENTBOARD_WATCH_HOME:-$HOME}"
}

_watch_xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

_watch_systemd_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

_watch_rmdir_if_empty() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  rmdir "$dir" 2>/dev/null || true
}

_watch_launchd_target() {
  local label="$1"
  printf 'gui/%s/%s' "$(id -u)" "$label"
}

_watch_log_path() {
  local slug="$1"
  printf '%s/.ab/watch-%s.log' "$(_watch_home)" "$slug"
}

_watch_install() {
  local interval="$1" threshold="$2"
  local sched; sched="$(_watch_scheduler)"
  [[ "$sched" != "unsupported" ]] || die "--install is only supported on macOS (launchd) and Linux (systemd)."

  local slug; slug="$(_watch_project_slug)"
  [[ -n "$slug" ]] || die "Could not derive a project slug from PWD ($PWD). Rename the directory to contain at least one alphanumeric character."
  local bin; bin="$(_watch_ab_bin)"
  local project_dir; project_dir="$(pwd)"
  local log_file; log_file="$(_watch_log_path "$slug")"

  mkdir -p "$(_watch_home)/.ab"

  if [[ "$sched" == "launchd" ]]; then
    _watch_install_launchd "$slug" "$bin" "$project_dir" "$log_file" "$interval" "$threshold"
  else
    _watch_install_systemd "$slug" "$bin" "$project_dir" "$log_file" "$interval" "$threshold"
  fi
}

_watch_install_launchd() {
  local slug="$1" bin="$2" project_dir="$3" log_file="$4" interval="$5" threshold="$6"
  local label="com.agentboard.${slug}"
  local plist_dir="$(_watch_home)/Library/LaunchAgents"
  local plist="$plist_dir/${label}.plist"
  local escaped_label escaped_bin escaped_project_dir escaped_log_file
  escaped_label="$(_watch_xml_escape "$label")"
  escaped_bin="$(_watch_xml_escape "$bin")"
  escaped_project_dir="$(_watch_xml_escape "$project_dir")"
  escaped_log_file="$(_watch_xml_escape "$log_file")"

  mkdir -p "$plist_dir"

  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${escaped_label}</string>
    <key>ProgramArguments</key>
    <array>
      <string>${escaped_bin}</string>
      <string>watch</string>
      <string>--once</string>
      <string>--quiet</string>
      <string>--threshold</string>
      <string>${threshold}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${escaped_project_dir}</string>
    <key>StartInterval</key>
    <integer>$((interval * 60))</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${escaped_log_file}</string>
    <key>StandardErrorPath</key>
    <string>${escaped_log_file}</string>
  </dict>
</plist>
EOF

  # bootstrap replaces the older `load` verb on modern macOS. Fall back on
  # failure so older systems still work.
  local gui_uid="gui/$(id -u)"
  local launchd_target
  launchd_target="$(_watch_launchd_target "$label")"
  launchctl bootout "${launchd_target}" 2>/dev/null || true
  if launchctl bootstrap "$gui_uid" "$plist" 2>/dev/null; then
    :
  elif launchctl load "$plist" 2>/dev/null; then
    :
  else
    warn "launchctl bootstrap + load both failed; plist written but not loaded. Try: launchctl load $plist"
    return 1
  fi

  if ! launchctl print "$launchd_target" >/dev/null 2>&1; then
    warn "launchctl did not load ${label}; plist written at $plist but scheduler is inactive."
    return 1
  fi

  ok "Installed launchd agent ${C_BOLD}${label}${C_RESET}"
  say "  ${C_DIM}plist:${C_RESET} $plist"
  say "  ${C_DIM}interval:${C_RESET} every ${interval} min  ${C_DIM}log:${C_RESET} $log_file"
  say "  ${C_DIM}check:${C_RESET} ab watch --status"
}

_watch_install_systemd() {
  local slug="$1" bin="$2" project_dir="$3" log_file="$4" interval="$5" threshold="$6"
  local unit="agentboard-${slug}"
  local unit_dir="$(_watch_home)/.config/systemd/user"
  local service="$unit_dir/${unit}.service"
  local timer="$unit_dir/${unit}.timer"
  local quoted_bin
  quoted_bin="$(_watch_systemd_quote "$bin")"

  mkdir -p "$unit_dir"

  cat > "$service" <<EOF
[Unit]
Description=Agentboard watch poll for ${slug}
After=network.target

[Service]
Type=oneshot
WorkingDirectory=${project_dir}
ExecStart=${quoted_bin} watch --once --quiet --threshold ${threshold}
StandardOutput=append:${log_file}
StandardError=append:${log_file}
EOF

  cat > "$timer" <<EOF
[Unit]
Description=Agentboard watch timer for ${slug}

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}min
Unit=${unit}.service

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload 2>/dev/null || true
  if ! systemctl --user enable --now "${unit}.timer" 2>/dev/null; then
    warn "systemctl --user enable failed; units written but timer not active. Try: systemctl --user enable --now ${unit}.timer"
    return 1
  fi

  ok "Installed systemd timer ${C_BOLD}${unit}.timer${C_RESET}"
  say "  ${C_DIM}service:${C_RESET} $service"
  say "  ${C_DIM}timer:${C_RESET}   $timer"
  say "  ${C_DIM}interval:${C_RESET} every ${interval} min  ${C_DIM}log:${C_RESET} $log_file"
  say "  ${C_DIM}check:${C_RESET} ab watch --status"
}
