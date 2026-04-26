cmd_watch() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local interval=10 threshold=1 stream="" stop=0 once=0 quiet=0
  local install=0 uninstall=0 status_mode=0
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
      --install) install=1; shift ;;
      --uninstall) uninstall=1; shift ;;
      --status) status_mode=1; shift ;;
      -h|--help) _watch_print_help; return 0 ;;
      *) die "Unknown flag for watch: $1" ;;
    esac
  done

  if (( install )); then
    _watch_install "$interval" "$threshold"
    return $?
  fi
  if (( uninstall )); then
    _watch_uninstall
    return $?
  fi
  if (( status_mode )); then
    _watch_status
    return $?
  fi

  if (( stop )); then
    _watch_stop
    return 0
  fi

  local -a streams=()
  if [[ -n "$stream" ]]; then
    streams=("$stream")
  else
    local _slug
    while IFS= read -r _slug; do
      [[ -n "$_slug" ]] && streams+=("$_slug")
    done < <(_watch_active_slugs)
    if (( ${#streams[@]} == 0 )); then
      printf '  \033[31m✖\033[0m  Could not auto-detect an active stream. Run '\''ab migrate --apply'\''\n     if streams lack frontmatter, or pass --stream <slug> explicitly.\n' >&2
      return 1
    fi
  fi

  local s sf
  for s in "${streams[@]}"; do
    [[ "$s" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case: $s"
    sf="./.platform/work/${s}.md"
    [[ -f "$sf" ]] || die "$sf not found. Create the stream first (ab new-stream)."
    has_frontmatter "$sf" || die "$sf has no v1 frontmatter. Run 'ab migrate --apply' first."
  done

  if (( once )); then
    for s in "${streams[@]}"; do
      _watch_poll_and_checkpoint "$s" "./.platform/work/${s}.md" "$threshold" "$quiet" || true
    done
    return 0
  fi

  local pid_file="./.platform/.watch.pid"
  if [[ -f "$pid_file" ]]; then
    local existing_pid; existing_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      die "A watch is already running (PID $existing_pid). Stop it first with: ab watch --stop"
    fi
    rm -f "$pid_file"
  fi

  local streams_label
  streams_label="$(printf '%s, ' "${streams[@]}" | sed 's/, $//')"
  if (( ${#streams[@]} == 1 )); then
    say "${C_BOLD}Watching${C_RESET} stream=${C_CYAN}${streams[0]}${C_RESET} interval=${interval}min threshold=${threshold}"
  else
    say "${C_BOLD}Watching${C_RESET} ${#streams[@]} streams: ${C_CYAN}${streams_label}${C_RESET} interval=${interval}min threshold=${threshold}"
  fi
  say "${C_DIM}Auto-checkpoints will fire when ≥ ${threshold} tracked file(s) changed since last poll.${C_RESET}"
  say "${C_DIM}Stop with:  ab watch --stop   (or Ctrl+C in this terminal)${C_RESET}"

  echo $$ > "$pid_file"
  trap "rm -f '$pid_file'; exit 0" INT TERM EXIT

  while true; do
    sleep "$((interval * 60))"
    for s in "${streams[@]}"; do
      _watch_poll_and_checkpoint "$s" "./.platform/work/${s}.md" "$threshold" "$quiet" || true
    done
  done
}

_watch_print_help() {
  cat <<'EOF'
Usage: ab watch [--interval MIN] [--threshold N] [--stream SLUG] [--once] [--stop]

Periodically polls `git status`. When ≥ threshold tracked files have changed
since the last poll, writes a mechanical checkpoint to each active stream so
state stays current across long Codex/Gemini sessions without manual input.

Defaults:
  --interval 10       Poll every 10 minutes.
  --threshold 1       Any change triggers a checkpoint.
  --stream <slug>     Watch a specific stream. If omitted, all active streams
                      are watched simultaneously.

Flags:
  --once              Run a single poll + checkpoint for all active streams, then exit.
  --stop              Stop the running watcher (uses PID file).
  --quiet             No stdout lines on successful checkpoint.
  --install           Install a per-project scheduler (launchd on macOS,
                      systemd user timer on Linux) so the poll runs
                      automatically every --interval minutes without needing
                      an open shell. Uses the current --interval/--threshold.
  --uninstall         Remove the scheduler for this project (reverse of --install).
  --status            Report install / active state + log file size + last-run.

Typical usage:
  ab watch --install      # once per project — auto-poll every 10 min
  ab watch --status       # check it's running
  ab watch &               # or: run in foreground for this shell
  ab watch --once          # manual sync right before switching CLIs
  ab watch --stop          # stop a foreground watcher
  ab watch --uninstall     # remove the scheduler

Environment:
  AGENTBOARD_WATCH_HOME  Override the HOME-rooted scheduler/log destination.
                         Useful for tests or local verification without
                         touching ~/Library/LaunchAgents or ~/.config/systemd.

Content written on each auto-checkpoint:
  --what   "(auto-watch) N file(s) modified since HH:MM: <list>"
  --next   (carried over from the stream's existing Resume state)
  --focus  highest-ranked changed file (prefers stream-relevant paths)

Skip rules:
  - If the stream file was touched in the last 5 min (e.g. the LLM just ran
    its own checkpoint), the watcher skips this tick — never clobbers fresh
    human/LLM-written state.
  - If the tracked dirty-state snapshot hasn't materially changed since the
    last auto-watch checkpoint, the watcher skips the duplicate tick.
  - If the stream's status is done/archived/closed, the watcher exits.
EOF
}

_watch_active_slugs() {
  local file status slug
  while IFS= read -r file; do
    status="$(frontmatter_value "$file" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    slug="$(frontmatter_value "$file" "slug")"
    [[ -n "$slug" ]] && printf '%s\n' "$slug"
  done < <(stream_files)
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

_watch_signature_dir() {
  printf '%s\n' "./.platform/.watch"
}

_watch_signature_file() {
  local stream="$1"
  printf '%s/%s.sig\n' "$(_watch_signature_dir)" "$stream"
}

_watch_path_from_porcelain_line() {
  local line="$1"
  local path=""
  if (( ${#line} > 3 )); then
    path="${line:3}"
  fi
  if [[ "$path" == *" -> "* ]]; then
    path="${path##* -> }"
  fi
  printf '%s\n' "$path"
}

_watch_is_untracked_line() {
  local line="$1"
  [[ "${line:0:2}" == "??" ]]
}

_watch_stream_tokens() {
  local stream="$1"
  printf '%s\n' "$stream" | tr '-' '\n' | awk 'length($0) >= 3 { print }'
}

_watch_path_score() {
  local stream="$1" path="$2"
  local lower_path score=0 token
  lower_path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

  case "$lower_path" in
    ".platform/work/${stream}.md") score=$((score + 80)) ;;
    .platform/work/*) score=$((score + 10)) ;;
    .platform/domains/*) score=$((score + 5)) ;;
    .claude/skills/*|.agents/skills/*|.codex/skills/*) score=$((score - 30)) ;;
    .claude/*|.agents/*|.codex/*) score=$((score - 15)) ;;
    .platform/*) score=$((score - 5)) ;;
    .*) score=$((score - 8)) ;;
  esac

  for token in $(_watch_stream_tokens "$stream"); do
    [[ -n "$token" ]] || continue
    if [[ "$lower_path" == *"$token"* ]]; then
      score=$((score + 25))
    fi
  done

  case "$lower_path" in
    src/*|lib/*|app/*|components/*|pages/*|tests/*|test/*|frontend/*|backend/*)
      score=$((score + 5))
      ;;
  esac

  printf '%s\n' "$score"
}

_watch_rank_paths() {
  local stream="$1"
  shift

  local -a paths=("$@")
  local -a scored=()
  local idx=0 score path

  for path in "${paths[@]}"; do
    score="$(_watch_path_score "$stream" "$path")"
    scored+=("${score}"$'\t'"${idx}"$'\t'"${path}")
    idx=$((idx + 1))
  done

  if (( ${#scored[@]} == 0 )); then
    return 0
  fi

  printf '%s\n' "${scored[@]}" \
    | sort -t "$(printf '\t')" -k1,1nr -k2,2n \
    | awk '{ sub(/^[^\t]*\t[^\t]*\t/, "", $0); print }'
}

_watch_best_path_score() {
  local stream="$1"
  shift

  local -a paths=("$@")
  if (( ${#paths[@]} == 0 )); then
    printf '%s\n' "-999"
    return 0
  fi

  local best score path
  best="$(_watch_path_score "$stream" "${paths[0]}")"
  for path in "${paths[@]}"; do
    score="$(_watch_path_score "$stream" "$path")"
    if (( score > best )); then
      best="$score"
    fi
  done
  printf '%s\n' "$best"
}

_watch_path_state() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'missing\n'
    return 0
  fi

  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f '%m:%z' "$path" 2>/dev/null || printf 'missing\n'
  else
    stat -c '%Y:%s' "$path" 2>/dev/null || printf 'missing\n'
  fi
}

_watch_signature_from_paths() {
  local changes="$1"
  shift

  local -a paths=("$@")
  local limit=0 path
  printf 'changes=%s\n' "$changes"
  for path in "${paths[@]}"; do
    printf '%s|%s\n' "$path" "$(_watch_path_state "$path")"
    limit=$((limit + 1))
    if (( limit >= 8 )); then
      break
    fi
  done
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

  local porcelain sig_file
  sig_file="$(_watch_signature_file "$stream")"
  porcelain="$(git status --porcelain 2>/dev/null || true)"
  if [[ -z "$porcelain" ]]; then
    rm -f "$sig_file"
    return 0
  fi

  local -a changed_paths=()
  local stream_rel_path=".platform/work/${stream}.md"
  local line path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if _watch_is_untracked_line "$line"; then
      continue
    fi
    path="$(_watch_path_from_porcelain_line "$line")"
    if [[ "$path" == "$stream_rel_path" ]]; then
      continue
    fi
    [[ -n "$path" ]] && changed_paths+=("$path")
  done <<< "$porcelain"

  local changes
  changes="${#changed_paths[@]}"
  [[ -z "$changes" ]] && changes=0
  if (( changes < threshold )); then
    rm -f "$sig_file"
    return 0
  fi

  local -a ranked_paths=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && ranked_paths+=("$path")
  done < <(_watch_rank_paths "$stream" "${changed_paths[@]}")

  local files focus prev_next what ts current_sig previous_sig count top_score
  files=""
  count=0
  for path in "${ranked_paths[@]}"; do
    if [[ -z "$files" ]]; then
      files="$path"
    else
      files="${files}, ${path}"
    fi
    count=$((count + 1))
    if (( count >= 5 )); then
      break
    fi
  done
  focus="${ranked_paths[0]:-}"
  top_score="$(_watch_best_path_score "$stream" "${ranked_paths[@]}")"
  if (( top_score < 0 )); then
    return 0
  fi
  current_sig="$(_watch_signature_from_paths "$changes" "${ranked_paths[@]}")"
  previous_sig="$(cat "$sig_file" 2>/dev/null || true)"
  if [[ -n "$previous_sig" && "$previous_sig" == "$current_sig" ]]; then
    return 0
  fi

  prev_next="$(stream_resume_field "$stream_file" "Next action" 2>/dev/null || true)"
  [[ -z "$prev_next" || "$prev_next" == "_not set_" ]] && prev_next="(continue — auto-watch update)"
  ts="$(date '+%H:%M')"
  what="(auto-watch) ${changes} file(s) modified since ${ts}: ${files}"

  if cmd_checkpoint "$stream" \
      --what "$what" \
      --next "$prev_next" \
      --focus "${focus:-—}" >/dev/null 2>&1; then
    mkdir -p "$(_watch_signature_dir)"
    printf '%s\n' "$current_sig" > "$sig_file"
    if (( ! quiet )); then
      printf '%s[watch %s] checkpoint: %s%s\n' "$C_DIM" "$ts" "$what" "$C_RESET" >&2
    fi
    return 0
  fi
  return 1
}

# ─── install/uninstall/status ────────────────────────────────────────────────

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
