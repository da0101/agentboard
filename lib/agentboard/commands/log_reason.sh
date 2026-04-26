cmd_log_reason() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  # Parse args: optional file path, then reason string
  # Signatures:
  #   ab log-reason "reason text"           (no file)
  #   ab log-reason src/auth.ts "reason"    (with file)
  #   ab log-reason --help

  local _file="" _reason=""
  case "${1:-}" in
    -h|--help) _log_reason_help; return 0 ;;
    "")        die "Usage: ab log-reason [<file>] \"<reason>\"" ;;
  esac

  # If 2 args: first is file, second is reason
  # If 1 arg: it's the reason (no file)
  if [[ $# -ge 2 ]]; then
    _file="${1#./}"   # normalize: strip leading ./
    _reason="$2"
  else
    _reason="$1"
  fi

  [[ -n "$_reason" ]] || die "Reason cannot be empty."

  local _provider="${AGENTBOARD_PROVIDER:-claude}"
  local _ts; _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

  _log_reason_stream_from_file() {
    local file="$1" slug=""
    [[ -n "$file" ]] || return 1

    case "$file" in
      .platform/work/*.md)
        slug="${file#.platform/work/}"
        ;;
      */.platform/work/*.md)
        slug="${file##*/.platform/work/}"
        ;;
      *)
        return 1
        ;;
    esac

    slug="${slug%.md}"
    case "$slug" in
      ACTIVE|BRIEF|TEMPLATE|"")
        return 1
        ;;
    esac

    stream_exists "$slug" || return 1
    printf '%s\n' "$slug"
  }

  # Resolve stream canonically, but prefer an explicit stream file target when
  # the reason is attached to work/<slug>.md itself.
  local _stream=""
  _stream="$(_log_reason_stream_from_file "$_file" 2>/dev/null || true)"
  if [[ -z "$_stream" ]]; then
    _stream="$(resolve_current_stream "" "${AGENTBOARD_SESSION_ID:-}" 2>/dev/null || true)"
  fi

  # Escape fields for JSON
  local _reason_e
  _reason_e="$(printf '%s' "$_reason" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\n/, "\\n"); printf "%s", $0 }')"
  local _file_e
  _file_e="$(printf '%s' "$_file" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s", $0 }')"
  local _stream_e
  _stream_e="$(printf '%s' "$_stream" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s", $0 }')"

  # Build the event payload
  local _payload
  if [[ -n "$_file" ]]; then
    _payload="{\"hook_event_name\":\"Reason\",\"ts\":\"$_ts\",\"provider\":\"$_provider\",\"stream\":\"$_stream_e\",\"file\":\"$_file_e\",\"reason\":\"$_reason_e\"}"
  else
    _payload="{\"hook_event_name\":\"Reason\",\"ts\":\"$_ts\",\"provider\":\"$_provider\",\"stream\":\"$_stream_e\",\"reason\":\"$_reason_e\"}"
  fi

  # Try daemon first, fall back to direct JSONL append
  local _log_file=".platform/events.jsonl"
  local _port_file=".platform/.daemon-port"
  local _written=0

  if [[ -f "$_port_file" ]] && command -v curl >/dev/null 2>&1; then
    local _port; _port="$(cat "$_port_file" 2>/dev/null)"
    if [[ "$_port" =~ ^[0-9]+$ ]]; then
      if curl -sf -m 2 -X POST "http://127.0.0.1:$_port/event" \
          -H 'Content-Type: application/json' \
          -d "$_payload" >/dev/null 2>&1; then
        _written=1
      fi
    fi
  fi

  if (( _written == 0 )); then
    mkdir -p "$(dirname "$_log_file")"
    printf '%s\n' "$_payload" >> "$_log_file" 2>/dev/null || true
    _written=1
  fi

  # Confirm to user
  if [[ -n "$_file" ]]; then
    ok "Reason logged for ${C_CYAN}${_file}${C_RESET}: ${C_DIM}${_reason}${C_RESET}"
  else
    ok "Reason logged: ${C_DIM}${_reason}${C_RESET}"
  fi
}

_log_reason_help() {
  cat <<'EOF'
ab log-reason [<file>] "<reason>"

Log a one-sentence explanation of WHY a change was made.
Written to .platform/events.jsonl so the next agent understands
the reasoning behind every significant edit.

Examples:
  ab log-reason src/auth.ts "Extracted token validation into middleware so Codex can call it without duplicating logic"
  ab log-reason "Removed legacy polling loop — replaced by daemon push events"

When to call it (after Write/Edit):
  - Refactors and extractions
  - Deletions of non-obvious code
  - New abstractions or interfaces
  - Architectural choices that aren't obvious from the code

Skip for: formatting, typo fixes, obvious variable renames.
EOF
}
