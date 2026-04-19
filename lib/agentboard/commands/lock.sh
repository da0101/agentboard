cmd_lock() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    acquire)  _lock_acquire "$@" ;;
    release)  _lock_release "$@" ;;
    list)     _lock_list ;;
    -h|--help) _lock_help ;;
    *) die "Unknown lock subcommand: $sub (acquire|release|list)" ;;
  esac
}

_lock_port() {
  local _port_file=".platform/.daemon-port"
  [[ -f "$_port_file" ]] || die "Daemon not running. Start it with: agentboard daemon start"
  local _port; _port="$(cat "$_port_file" 2>/dev/null || true)"
  [[ "$_port" =~ ^[0-9]+$ ]] || die "Daemon not running. Start it with: agentboard daemon start"
  printf '%s' "$_port"
}

_lock_session_id() {
  local _provider="$1"
  if [[ -n "${AGENTBOARD_SESSION_ID:-}" ]]; then
    printf '%s' "$AGENTBOARD_SESSION_ID"
  else
    printf '%s' "${_provider}-ppid-${PPID}"
  fi
}

_lock_acquire() {
  local _file="${1:-}"
  [[ -n "$_file" ]] || die "Usage: agentboard lock acquire <file>"
  _file="${_file#./}"  # normalize: strip leading ./

  command -v curl >/dev/null 2>&1 || die "curl is required for 'agentboard lock acquire'."
  local _port; _port="$(_lock_port)"
  local _provider="${AGENTBOARD_PROVIDER:-codex}"
  local _session_id; _session_id="$(_lock_session_id "$_provider")"

  local _deadline=$(( $(date +%s) + 30 ))
  local _first=1
  while true; do
    local _resp _code
    _resp="$(curl -sf -m 2 -w '\n%{http_code}' -X POST "http://127.0.0.1:${_port}/lock" \
      -H 'Content-Type: application/json' \
      -d "{\"file\":\"$_file\",\"provider\":\"$_provider\",\"session_id\":\"$_session_id\"}" 2>/dev/null || true)"
    _code="$(printf '%s' "$_resp" | tail -1)"

    if [[ "$_code" == "200" ]]; then
      ok "Lock acquired: $_file"
      return 0
    elif [[ "$_code" == "202" ]]; then
      local _holder _holder_session _holder_display
      _holder="$(printf '%s' "$_resp" | head -1 | grep -o '"holder"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')"
      _holder_session="$(printf '%s' "$_resp" | head -1 | grep -o '"holder_session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')"
      _holder_display="${_holder:-unknown}"
      [[ -n "$_holder_session" ]] && _holder_display="${_holder_display}/${_holder_session}"
      if (( _first )); then
        say "${C_DIM}Waiting for lock on $_file (held by ${_holder_display})...${C_RESET}"
        _first=0
      fi
      if [[ "$(date +%s)" -ge "$_deadline" ]]; then
        warn "Lock timeout on $_file — proceeding anyway"
        return 0
      fi
      sleep 1
    else
      warn "Daemon unreachable — proceeding without lock on $_file"
      return 0
    fi
  done
}

_lock_release() {
  local _file="${1:-}"
  [[ -n "$_file" ]] || die "Usage: agentboard lock release <file>"
  _file="${_file#./}"

  command -v curl >/dev/null 2>&1 || return 0
  local _port_file=".platform/.daemon-port"
  [[ -f "$_port_file" ]] || return 0
  local _port; _port="$(cat "$_port_file" 2>/dev/null || true)"
  [[ "$_port" =~ ^[0-9]+$ ]] || return 0
  local _provider="${AGENTBOARD_PROVIDER:-codex}"
  local _session_id; _session_id="$(_lock_session_id "$_provider")"

  curl -sf -m 2 -X DELETE "http://127.0.0.1:${_port}/lock" \
    -H 'Content-Type: application/json' \
    -d "{\"file\":\"$_file\",\"provider\":\"$_provider\",\"session_id\":\"$_session_id\"}" >/dev/null 2>&1 || true

  ok "Lock released: $_file"
}

_lock_list() {
  # No daemon = nothing locked. Informational only — never error.
  local _port_file=".platform/.daemon-port"
  if ! command -v curl >/dev/null 2>&1 || [[ ! -f "$_port_file" ]]; then
    say "${C_DIM}No files currently locked.${C_RESET}"
    return 0
  fi
  local _port; _port="$(cat "$_port_file" 2>/dev/null || true)"
  [[ "$_port" =~ ^[0-9]+$ ]] || { say "${C_DIM}No files currently locked.${C_RESET}"; return 0; }

  local _resp
  _resp="$(curl -sf -m 2 "http://127.0.0.1:${_port}/locks" 2>/dev/null || true)"

  if [[ -z "$_resp" ]]; then
    say "${C_DIM}No files currently locked.${C_RESET}"
    return 0
  fi

  # Check for empty array
  local _trimmed; _trimmed="$(printf '%s' "$_resp" | tr -d '[:space:]')"
  if [[ "$_trimmed" == "[]" ]]; then
    say "${C_DIM}No files currently locked.${C_RESET}"
    return 0
  fi

  printf '\n%s%sFile locks%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

  if command -v jq >/dev/null 2>&1; then
    printf '%s%-45s  %-12s  %-10s  %s%s\n' \
      "$C_BOLD" "FILE" "HOLDER" "HELD" "QUEUE" "$C_RESET"
    printf '%s\n' "$_resp" | jq -r '
      .[] |
      [
        .file,
        (.holder + (if (.holder_session_id // "") != "" then "/" + .holder_session_id else "" end)),
        ((.held_seconds | tostring) + "s"),
        (
          if (.queue_details // []) | length > 0 then
            (.queue_details | map(.provider + "/" + .session_id) | join(","))
          else
            ""
          end
        )
      ] | @tsv
    ' 2>/dev/null \
      | while IFS=$'\t' read -r _f _h _s _q; do
          printf '%-45s  %s%-12s%s  %-10s  %s%s%s\n' \
            "$_f" "$C_CYAN" "$_h" "$C_RESET" "$_s" "$C_DIM" "${_q:-—}" "$C_RESET"
        done
  else
    # No jq — raw output with a header
    printf '%s%-45s  %-12s  %-10s  %s%s\n' \
      "$C_BOLD" "FILE" "HOLDER" "HELD" "QUEUE" "$C_RESET"
    printf '%s\n' "$_resp" | grep -o '"file"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | grep -o '"[^"]*"$' | tr -d '"' \
      | while IFS= read -r _f; do
          printf '  %s%s%s\n' "$C_CYAN" "$_f" "$C_RESET"
        done
    say
    say "${C_DIM}Install jq for full table output.${C_RESET}"
  fi
  say
}

_lock_help() {
  cat <<'EOF'
agentboard lock <subcommand>

  acquire <file>   Acquire exclusive write lock on a file (blocks until granted)
  release <file>   Release a held lock
  list             Show all currently locked files and queues

Used by Codex/Gemini to coordinate file edits with Claude Code.
Claude Code acquires/releases locks automatically via PreToolUse/PostToolUse hooks.
EOF
}
