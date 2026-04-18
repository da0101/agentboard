cmd_daemon() {
  local sub="${1:-help}"
  shift || true

  case "$sub" in
    start)        _daemon_start ;;
    stop)         _daemon_stop ;;
    status)       _daemon_status ;;
    -h|--help)    _daemon_help ;;
    *)            die "Unknown daemon subcommand: $sub (see 'agentboard daemon --help')" ;;
  esac
}

_daemon_start() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local _daemon_js="$AGENTBOARD_ROOT/bin/agentboard-daemon.js"
  [[ -f "$_daemon_js" ]] || die "agentboard-daemon.js not found at $_daemon_js"

  # Already running?
  if [[ -f ".platform/.daemon-port" ]]; then
    local _existing_port; _existing_port="$(cat .platform/.daemon-port 2>/dev/null || true)"
    if [[ -n "$_existing_port" ]] && curl -sf "http://127.0.0.1:${_existing_port}/health" >/dev/null 2>&1; then
      say "Daemon already running on port ${_existing_port}"
      return 0
    fi
    # Stale port file — remove it
    rm -f ".platform/.daemon-port"
  fi

  command -v node >/dev/null 2>&1 || die "node is required for 'agentboard daemon'. Install Node.js 18+."

  node "$_daemon_js" \
    "$(pwd)/.platform/events.jsonl" \
    "$(pwd)/.platform/.daemon-port" \
    >/dev/null 2>&1 &

  local _bg_pid=$!

  # Wait up to 3s for the port file to appear (daemon writes it after bind)
  local _waited=0
  while [[ ! -f ".platform/.daemon-port" ]]; do
    sleep 0.2
    _waited=$(( _waited + 1 ))
    if (( _waited >= 15 )); then
      die "Daemon failed to start (no port file after 3s)"
    fi
  done

  ok "Daemon started on port $(cat .platform/.daemon-port) (PID: $_bg_pid)"
}

_daemon_stop() {
  if [[ ! -f ".platform/.daemon-port" ]]; then
    say "Daemon not running."
    return 0
  fi

  local _port; _port="$(cat .platform/.daemon-port 2>/dev/null || true)"
  # Ask daemon to shut down; ignore errors (it may already be gone)
  curl -sf "http://127.0.0.1:${_port}/shutdown" >/dev/null 2>&1 || true

  # Wait up to 2s for port file to disappear
  local _waited=0
  while [[ -f ".platform/.daemon-port" ]]; do
    sleep 0.2
    _waited=$(( _waited + 1 ))
    if (( _waited >= 10 )); then
      break
    fi
  done

  # Clean up stale port file if daemon didn't remove it
  [[ -f ".platform/.daemon-port" ]] && rm -f ".platform/.daemon-port"

  ok "Daemon stopped."
}

_daemon_status() {
  if [[ ! -f ".platform/.daemon-port" ]]; then
    say "Daemon: stopped"
    return 0
  fi

  local _port; _port="$(cat .platform/.daemon-port 2>/dev/null || true)"
  local _health
  if _health="$(curl -sf "http://127.0.0.1:${_port}/health" 2>/dev/null)"; then
    local _events
    _events="$(printf '%s' "$_health" | awk 'match($0, /"events"[[:space:]]*:[[:space:]]*[0-9]+/) {
      s = substr($0, RSTART, RLENGTH)
      sub(/.*:[[:space:]]*/, "", s)
      print s; exit
    }')"
    say "Daemon: ${C_GREEN}running${C_RESET} on port ${_port} — ${_events:-0} events logged"
  else
    warn "Stale port file at .platform/.daemon-port (port ${_port} not responding)"
    say "  Run: ${C_BOLD}agentboard daemon start${C_RESET}"
  fi
}

_daemon_help() {
  cat <<'EOF'
agentboard daemon <subcommand>

  start     Start the event daemon (requires node 18+)
  stop      Stop the running daemon
  status    Show daemon state and event count

The daemon serializes events from all providers into .platform/events.jsonl.
Run it before launching parallel agent sessions.
EOF
}
