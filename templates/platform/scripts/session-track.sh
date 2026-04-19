#!/usr/bin/env bash
# session-track.sh — shared helpers for provider wrappers (codex-ab, gemini-ab).
#
# Closes the cross-provider observability gap. Claude Code has native hooks
# that fire on every tool call; Codex and Gemini don't. This module gives the
# wrappers equivalent visibility by:
#
#   1. Logging SessionStart / SessionEnd events to events.jsonl.
#   2. Running a background poller during the session that detects file
#      changes every N seconds and writes one event per change — the same
#      stream of data Claude Code hooks produce, just inferred from the
#      filesystem instead of a native API.
#
# Meant to be sourced, not executed. The caller (wrapper) exports
# AGENTBOARD_PROVIDER and AGENTBOARD_SESSION_ID before calling these fns.

_ab_events_hook=".platform/scripts/hooks/event-logger.sh"

_ab_session_event() {
  local kind="$1" session_id="$2" extra="${3:-}"
  [[ -f "$_ab_events_hook" ]] || return 0
  local payload
  local stream_extra=""
  if [[ -n "${AGENTBOARD_STREAM:-}" ]]; then
    stream_extra="\"stream\":\"$AGENTBOARD_STREAM\""
  fi
  if [[ -n "$stream_extra" && -n "$extra" ]]; then
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\",${stream_extra},$extra}"
  elif [[ -n "$stream_extra" ]]; then
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\",${stream_extra}}"
  elif [[ -n "$extra" ]]; then
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\",$extra}"
  else
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\"}"
  fi
  printf '%s' "$payload" | bash "$_ab_events_hook" 2>/dev/null || true
}

# Best-effort: start daemon if not already running.
# Sets _ab_daemon_was_started=1 so the caller can stop it on exit.
_ab_daemon_was_started=0
_ab_ensure_daemon() {
  command -v agentboard >/dev/null 2>&1 || return 0
  command -v node >/dev/null 2>&1 || return 0
  [[ -d ".platform" ]] || return 0
  local _pf=".platform/.daemon-port"
  if [[ -f "$_pf" ]]; then
    local _p; _p="$(cat "$_pf" 2>/dev/null)"
    if [[ "$_p" =~ ^[0-9]+$ ]] && curl -sf -m 1 "http://127.0.0.1:$_p/health" >/dev/null 2>&1; then
      return 0  # already running
    fi
  fi
  agentboard daemon start >/dev/null 2>&1 || return 0
  _ab_daemon_was_started=1
}

_ab_stop_daemon() {
  [[ "$_ab_daemon_was_started" -eq 1 ]] || return 0
  command -v agentboard >/dev/null 2>&1 || return 0
  agentboard daemon stop >/dev/null 2>&1 || true
  _ab_daemon_was_started=0
}

# Start a background file-change poller. Writes one event per changed tracked
# file per poll interval. Returns the poller PID; caller must stop it on exit.
#
# Args: session_id  provider  [interval_seconds=5]
_ab_start_file_poller() {
  local session_id="$1" provider="$2" interval="${3:-5}"
  [[ -f "$_ab_events_hook" ]] || { printf '0'; return 0; }
  command -v git >/dev/null 2>&1 || { printf '0'; return 0; }
  git rev-parse --git-dir >/dev/null 2>&1 || { printf '0'; return 0; }
  _ab_ensure_daemon 2>/dev/null || true

  # Capture baseline SYNCHRONOUSLY before backgrounding. If we let the
  # backgrounded subshell compute it, fork latency allows file modifications
  # to sneak into the baseline — making the very change we wanted to observe
  # invisible. The baseline hashes the full diff *content* (not just
  # filenames), so repeated edits to the same file are always detected.
  local _baseline_sig
  _baseline_sig="$(git diff HEAD 2>/dev/null | shasum 2>/dev/null | awk '{print $1}')"
  [[ -z "$_baseline_sig" ]] && _baseline_sig="-"

  (
    # Subshell — variables are scoped automatically, no `local` needed.
    _hook="$_ab_events_hook"
    _provider_env="$provider"
    _stream_env="${AGENTBOARD_STREAM:-}"
    _prev_sig="$_baseline_sig"
    _logged_files=""

    while sleep "$interval"; do
      _cur_diff="$(git diff HEAD 2>/dev/null)"
      _cur_sig="$(printf '%s' "$_cur_diff" | shasum 2>/dev/null | awk '{print $1}')"
      [[ -z "$_cur_sig" ]] && _cur_sig="-"
      [[ "$_cur_sig" == "$_prev_sig" ]] && continue

      # Only log files not yet seen this session — prevents re-emitting all
      # previously-changed files every time any single file changes.
      _changed="$(git diff --name-only HEAD 2>/dev/null | sort -u)"
      _new_files=""
      while IFS= read -r _f; do
        [[ -n "$_f" ]] || continue
        printf '%s\n' "$_logged_files" | grep -qxF "$_f" 2>/dev/null && continue
        _logged_files="${_logged_files}${_f}"$'\n'
        _new_files="${_new_files}${_f}"$'\n'
      done <<< "$_changed"
      _prev_sig="$_cur_sig"
      [[ -z "$_new_files" ]] && continue

      while IFS= read -r _f; do
        [[ -n "$_f" ]] || continue
        if [[ -n "$_stream_env" ]]; then
          _payload="{\"hook_event_name\":\"FileChange\",\"session_id\":\"$session_id\",\"stream\":\"$_stream_env\",\"tool_name\":\"_observed_edit\",\"file_path\":\"$_f\"}"
        else
          _payload="{\"hook_event_name\":\"FileChange\",\"session_id\":\"$session_id\",\"tool_name\":\"_observed_edit\",\"file_path\":\"$_f\"}"
        fi
        # AGENTBOARD_PROVIDER must be set for the *hook* process (right side
        # of the pipe) — setting it on the printf is a no-op for the hook.
        printf '%s' "$_payload" | AGENTBOARD_PROVIDER="$_provider_env" AGENTBOARD_STREAM="$_stream_env" bash "$_hook" 2>/dev/null || true
      done <<< "$_new_files"
    done
  ) >/dev/null 2>&1 &
  printf '%s' $!
}

_ab_stop_file_poller() {
  local pid="${1:-0}"
  [[ "$pid" -gt 0 ]] 2>/dev/null || return 0
  kill "$pid" 2>/dev/null || true
  # `wait` only reaps direct children of the current shell. When the poller
  # is spawned via $(...), it's already orphaned, so wait returns immediately
  # and the process may still be sleeping. Poll for up to 2 seconds, then
  # escalate to SIGKILL if it's stuck (e.g. in a long `shasum` call).
  local _i
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done
  kill -9 "$pid" 2>/dev/null || true
}
