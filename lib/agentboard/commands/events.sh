cmd_events() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local sub="${1:-tail}"
  shift || true

  case "$sub" in
    tail)        _events_tail "$@" ;;
    since)       _events_since "$@" ;;
    stream)      _events_stream "$@" ;;
    stats)       _events_stats ;;
    clear)       _events_clear "$@" ;;
    rotate)      _events_rotate "$@" ;;
    archive)     _events_archive ;;
    path)        printf '%s\n' "$(_events_log_path)" ;;
    -h|--help)   _events_print_help ;;
    *)           die "Unknown events subcommand: $sub (see 'agentboard events --help')" ;;
  esac
}

_events_log_path() {
  printf '%s' "./.platform/events.jsonl"
}

_events_tail() {
  local n=20 json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        [[ -n "${2:-}" ]] || die "events tail: -n requires a number"
        n="$2"; shift 2 ;;
      --json) json=1; shift ;;
      *) die "Unknown flag for events tail: $1" ;;
    esac
  done
  [[ "$n" =~ ^[0-9]+$ ]] || die "events tail: -n must be a positive integer"

  local log; log="$(_events_log_path)"
  if [[ ! -f "$log" ]]; then
    say "${C_DIM}No events logged yet. Events are captured by the PostToolUse hook in .claude/settings.json.${C_RESET}"
    return 0
  fi

  if (( json )); then
    command tail -n "$n" "$log"
    return 0
  fi

  printf '\n%s%sagentboard events (last %s)%s\n\n' "$C_BOLD" "$C_CYAN" "$n" "$C_RESET"
  _events_pretty_print "$(command tail -n "$n" "$log")"
}

_events_since() {
  local ts="${1:-}" json=0
  [[ -n "$ts" ]] || die "Usage: agentboard events since <ISO-timestamp> [--json]"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      *) die "Unknown flag for events since: $1" ;;
    esac
  done

  local log; log="$(_events_log_path)"
  [[ -f "$log" ]] || { say "${C_DIM}No events logged yet.${C_RESET}"; return 0; }

  local filtered
  filtered="$(awk -v cutoff="$ts" '
    {
      if (match($0, /"ts"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^"ts"[[:space:]]*:[[:space:]]*"/, "", s)
        sub(/"$/, "", s)
        if (s >= cutoff) print
      }
    }' "$log")"

  if (( json )); then
    [[ -n "$filtered" ]] && printf '%s\n' "$filtered"
    return 0
  fi

  printf '\n%s%sagentboard events since %s%s\n\n' "$C_BOLD" "$C_CYAN" "$ts" "$C_RESET"
  _events_pretty_print "$filtered"
}

_events_stream() {
  local slug="${1:-}" json=0
  [[ -n "$slug" ]] || die "Usage: agentboard events stream <slug> [--json]"
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      *) die "Unknown flag for events stream: $1" ;;
    esac
  done

  local log; log="$(_events_log_path)"
  [[ -f "$log" ]] || { say "${C_DIM}No events logged yet.${C_RESET}"; return 0; }

  local filtered
  filtered="$(awk -v target="$slug" '
    {
      if (match($0, /"stream"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^"stream"[[:space:]]*:[[:space:]]*"/, "", s)
        sub(/"$/, "", s)
        if (s == target) print
      }
    }' "$log")"

  if (( json )); then
    [[ -n "$filtered" ]] && printf '%s\n' "$filtered"
    return 0
  fi

  printf '\n%s%sagentboard events for stream %s%s\n\n' "$C_BOLD" "$C_CYAN" "$slug" "$C_RESET"
  _events_pretty_print "$filtered"
}

_events_stats() {
  local log; log="$(_events_log_path)"
  if [[ ! -f "$log" ]]; then
    say "${C_DIM}No events logged yet.${C_RESET}"
    return 0
  fi

  local total first last
  total="$(awk 'END { print NR }' "$log")"
  first="$(awk 'NR==1 {
    if (match($0, /"ts"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
      s = substr($0, RSTART, RLENGTH); sub(/^"ts"[[:space:]]*:[[:space:]]*"/, "", s); sub(/"$/, "", s); print s; exit
    }
  }' "$log")"
  last="$(awk 'END {
    if (match($0, /"ts"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
      s = substr($0, RSTART, RLENGTH); sub(/^"ts"[[:space:]]*:[[:space:]]*"/, "", s); sub(/"$/, "", s); print s
    }
  }' "$log")"

  printf '\n%s%sevents log stats%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  file:    %s\n' "$log"
  printf '  events:  %s\n' "$total"
  printf '  first:   %s\n' "${first:-—}"
  printf '  last:    %s\n' "${last:-—}"

  printf '\n%sTop tools:%s\n' "$C_BOLD" "$C_RESET"
  awk 'match($0, /"tool"[[:space:]]*:[[:space:]]*"[^"]*"/) {
    s = substr($0, RSTART, RLENGTH); sub(/^"tool"[[:space:]]*:[[:space:]]*"/, "", s); sub(/"$/, "", s)
    if (s != "") counts[s]++
  } END {
    for (k in counts) printf "  %-20s %d\n", k, counts[k]
  }' "$log" | sort -k2 -n -r | command head -5 || true
  say
}

_events_clear() {
  local confirm=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      *) die "Unknown flag for events clear: $1" ;;
    esac
  done

  local log; log="$(_events_log_path)"
  [[ -f "$log" ]] || { ok "Events log already empty."; return 0; }

  local size; size="$(awk 'END { print NR }' "$log")"
  if (( ! confirm )); then
    printf '\n%s%sagentboard events clear (preview)%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  would archive: %s (%s events)\n' "$log" "$size"
    printf '  archive path:  %s.archive-<ts>\n\n' "$log"
    printf '%sPreview only. Re-run with --confirm to archive.%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local ts; ts="$(date +%s)"
  local archive="${log}.archive-${ts}"
  mv "$log" "$archive"
  ok "Archived $size event(s) to $archive"
}

_events_rotate() {
  local force=0 threshold=5000
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)         force=1; shift ;;
      --threshold)
        [[ -n "${2:-}" ]] || die "events rotate: --threshold requires a number"
        threshold="$2"; shift 2 ;;
      *) die "Unknown flag for events rotate: $1" ;;
    esac
  done

  local log; log="$(_events_log_path)"
  [[ -f "$log" ]] || { ok "events.jsonl does not exist — nothing to rotate."; return 0; }

  local line_count
  line_count="$(awk 'NF' "$log" | wc -l | tr -d ' ')"

  if (( ! force && line_count < threshold )); then
    say "events.jsonl has ${line_count} lines (threshold: ${threshold}). Use --force to rotate anyway."
    return 0
  fi

  # If daemon is running, delegate via /rotate endpoint
  if [[ -f ".platform/.daemon-port" ]]; then
    local _port; _port="$(cat .platform/.daemon-port 2>/dev/null || true)"
    if [[ -n "$_port" ]] && curl -sf "http://127.0.0.1:${_port}/health" >/dev/null 2>&1; then
      curl -sf "http://127.0.0.1:${_port}/rotate" >/dev/null 2>&1 || true
      ok "Rotated events.jsonl via daemon (${line_count} lines archived)"
      return 0
    fi
  fi

  # No daemon — rotate directly in bash
  local today; today="$(date +%Y-%m-%d)"
  local dir=".platform"
  local archive="${dir}/events-${today}.jsonl"

  # Append to archive (creates if absent, accumulates if already exists)
  cat "$log" >> "$archive"
  # Truncate the live file
  printf '' > "$log"

  ok "Rotated events.jsonl → events-${today}.jsonl (${line_count} lines archived)"
}

_events_archive() {
  local dir=".platform"
  local found=0

  printf '\n%s%sarchived event logs%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  %-35s  %8s  %s\n' "file" "lines" "size"
  printf '  %-35s  %8s  %s\n' "----" "-----" "----"

  # nullglob-safe iteration
  local f
  for f in "${dir}"/events-*.jsonl; do
    [[ -e "$f" ]] || continue
    found=1
    local fname; fname="$(basename "$f")"
    local lines; lines="$(awk 'NF' "$f" | wc -l | tr -d ' ')"
    local size; size="$(du -sh "$f" 2>/dev/null | cut -f1 || printf '?')"
    printf '  %-35s  %8s  %s\n' "$fname" "$lines" "$size"
  done

  if (( ! found )); then
    say "${C_DIM}No archived event logs.${C_RESET}"
  fi
  say
}

_events_pretty_print() {
  local content="$1"
  if [[ -z "$content" ]]; then
    say "${C_DIM}(no matching events)${C_RESET}"
    return 0
  fi
  printf '%s\n' "$content" | awk '
    function extract(key,   s, re) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
      if (match($0, re)) {
        s = substr($0, RSTART, RLENGTH)
        sub("^\"" key "\"[[:space:]]*:[[:space:]]*\"", "", s)
        sub("\"$", "", s)
        return s
      }
      return ""
    }
    {
      ts = extract("ts")
      provider = extract("provider")
      stream = extract("stream")
      tool = extract("tool")
      hook = extract("hook_event_name")
      reason = extract("reason")
      file = extract("file")

      if (hook == "Reason") {
        label = (file != "" ? "→ " file ": " : "→ ") reason
      } else if (tool != "") {
        label = tool
      } else {
        label = "(non-tool event)"
      }
      printf "  %s  %-7s  %-18s  %s\n", ts, provider, (stream == "" ? "—" : stream), label
    }'
  say
}

_events_print_help() {
  cat <<'EOF'
Usage: agentboard events <subcommand> [flags]

Subcommands:
  tail [-n N] [--json]          Last N events (default 20). --json = raw JSONL.
  since <ISO-ts> [--json]       All events at or after <ISO-ts> (e.g. 2026-04-18T12:00:00Z).
  stream <slug> [--json]        All events tagged with this stream.
  stats                         Event count + top tools.
  clear [--confirm]             Archive the current log (preview by default).
  rotate [--force] [--threshold N]  Rotate events.jsonl → events-YYYY-MM-DD.jsonl.
  archive                       List all archived event log files.
  path                          Print the log file path.

The events log is written by a PostToolUse hook at .platform/scripts/hooks/
event-logger.sh. It records one JSON line per tool call from any provider
(Claude, Codex, Gemini). Cross-provider orchestration is: agent A writes,
agent B reads the tail for context.

Example handoff flow:
  # Agent A session ends
  agentboard checkpoint login --what "..." --next "..."

  # Agent B session starts
  agentboard events stream login --json | tail -20
  # ^ paste into Agent B's prompt for full tool-call history
EOF
}
