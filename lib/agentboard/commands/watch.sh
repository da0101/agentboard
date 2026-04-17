cmd_watch() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local interval=10 threshold=1 stream="" stop=0 once=0 quiet=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval)
        [[ -n "${2:-}" ]] || die "watch requires a value after --interval"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--interval must be a positive integer (minutes)"
        interval="$2"; shift 2 ;;
      --threshold)
        [[ -n "${2:-}" ]] || die "watch requires a value after --threshold"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--threshold must be a positive integer"
        threshold="$2"; shift 2 ;;
      --stream)
        [[ -n "${2:-}" ]] || die "watch requires a value after --stream"
        stream="$2"; shift 2 ;;
      --stop) stop=1; shift ;;
      --once) once=1; shift ;;
      --quiet) quiet=1; shift ;;
      -h|--help) _watch_print_help; return 0 ;;
      *) die "Unknown flag for watch: $1" ;;
    esac
  done

  if (( stop )); then
    _watch_stop
    return 0
  fi

  if [[ -z "$stream" ]]; then
    stream="$(_watch_auto_detect_stream)" \
      || die "Could not auto-detect an active stream. Pass --stream <slug> explicitly."
  fi
  [[ "$stream" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local stream_file="./.platform/work/${stream}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (agentboard new-stream)."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  if (( once )); then
    _watch_poll_and_checkpoint "$stream" "$stream_file" "$threshold" "$quiet"
    return 0
  fi

  local pid_file="./.platform/.watch.pid"
  if [[ -f "$pid_file" ]]; then
    local existing_pid; existing_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      die "A watch is already running (PID $existing_pid). Stop it first with: agentboard watch --stop"
    fi
    rm -f "$pid_file"
  fi

  say "${C_BOLD}Watching${C_RESET} stream=${C_CYAN}${stream}${C_RESET} interval=${interval}min threshold=${threshold}"
  say "${C_DIM}Auto-checkpoints will fire when ≥ ${threshold} tracked file(s) changed since last poll.${C_RESET}"
  say "${C_DIM}Stop with:  agentboard watch --stop   (or Ctrl+C in this terminal)${C_RESET}"

  echo $$ > "$pid_file"
  trap "rm -f '$pid_file'; exit 0" INT TERM EXIT

  while true; do
    sleep "$((interval * 60))"
    _watch_poll_and_checkpoint "$stream" "$stream_file" "$threshold" "$quiet" || true
  done
}

_watch_print_help() {
  cat <<'EOF'
Usage: agentboard watch [--interval MIN] [--threshold N] [--stream SLUG] [--once] [--stop]

Periodically polls `git status`. When ≥ threshold tracked files have changed
since the last poll, writes a mechanical checkpoint to the active stream so
state stays current across long Codex/Gemini sessions without manual input.

Defaults:
  --interval 10       Poll every 10 minutes.
  --threshold 1       Any change triggers a checkpoint.
  --stream <slug>     Auto-detected from work/ACTIVE.md if exactly one
                      stream is active; otherwise required.

Flags:
  --once              Run a single poll + checkpoint, then exit.
  --stop              Stop the running watcher (uses PID file).
  --quiet             No stdout lines on successful checkpoint.

Typical usage:
  agentboard watch &              # background daemon for the day
  agentboard watch --once          # manual sync right before switching CLIs
  agentboard watch --stop          # end of day

Content written on each auto-checkpoint:
  --what   "(auto-watch) N file(s) modified since HH:MM: <list>"
  --next   (carried over from the stream's existing Resume state)
  --focus  most-recently-modified tracked file

Skip rules:
  - If the stream file was touched in the last 5 min (e.g. the LLM just ran
    its own checkpoint), the watcher skips this tick — never clobbers fresh
    human/LLM-written state.
  - If the stream's status is done/archived/closed, the watcher exits.
EOF
}

_watch_auto_detect_stream() {
  local -a active=()
  local file status slug
  while IFS= read -r file; do
    status="$(frontmatter_value "$file" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    slug="$(frontmatter_value "$file" "slug")"
    [[ -n "$slug" ]] && active+=("$slug")
  done < <(stream_files)

  if (( ${#active[@]} == 0 )); then
    return 1
  fi
  if (( ${#active[@]} > 1 )); then
    return 1
  fi
  printf '%s\n' "${active[0]}"
}

_watch_stop() {
  local pid_file="./.platform/.watch.pid"
  if [[ ! -f "$pid_file" ]]; then
    say "${C_DIM}No watcher running (no PID file at $pid_file).${C_RESET}"
    return 0
  fi
  local pid; pid="$(cat "$pid_file" 2>/dev/null || echo "")"
  rm -f "$pid_file"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    ok "Watcher stopped (PID $pid)."
  else
    say "${C_DIM}PID file removed; no live process was attached.${C_RESET}"
  fi
}

_watch_poll_and_checkpoint() {
  local stream="$1" stream_file="$2" threshold="$3" quiet="${4:-0}"

  [[ -f "$stream_file" ]] || return 0
  local status
  status="$(frontmatter_value "$stream_file" "status")"
  case "$status" in done|archived|closed) return 0 ;; esac

  # Skip if stream file was touched in the last 5 minutes (fresh manual checkpoint)
  local mtime now
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime="$(stat -f %m "$stream_file" 2>/dev/null || echo 0)"
  else
    mtime="$(stat -c %Y "$stream_file" 2>/dev/null || echo 0)"
  fi
  now="$(date +%s)"
  if (( now - mtime < 300 )); then
    return 0
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  local porcelain
  porcelain="$(git status --porcelain 2>/dev/null || true)"
  if [[ -z "$porcelain" ]]; then
    return 0
  fi

  local changes
  changes="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
  [[ -z "$changes" ]] && changes=0
  if (( changes < threshold )); then
    return 0
  fi

  local files focus prev_next what ts
  files="$(printf '%s\n' "$porcelain" | awk '
    NR <= 5 {
      line = $0
      sub(/^.{2}[[:space:]]?/, "", line)
      printf "%s%s", (printed ? ", " : ""), line
      printed = 1
    }
  ')"
  focus="$(printf '%s\n' "$porcelain" | awk '
    NR == 1 {
      line = $0
      sub(/^.{2}[[:space:]]?/, "", line)
      print line
      exit
    }
  ')"
  prev_next="$(stream_resume_field "$stream_file" "Next action" 2>/dev/null || true)"
  [[ -z "$prev_next" || "$prev_next" == "_not set_" ]] && prev_next="(continue — auto-watch update)"
  ts="$(date '+%H:%M')"
  what="(auto-watch) ${changes} file(s) modified since ${ts}: ${files}"

  if cmd_checkpoint "$stream" \
      --what "$what" \
      --next "$prev_next" \
      --focus "${focus:-—}" >/dev/null 2>&1; then
    if (( ! quiet )); then
      printf '%s[watch %s] checkpoint: %s%s\n' "$C_DIM" "$ts" "$what" "$C_RESET" >&2
    fi
    return 0
  fi
  return 1
}
