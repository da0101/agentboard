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
  if [[ -n "$extra" ]]; then
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\",$extra}"
  else
    payload="{\"hook_event_name\":\"$kind\",\"session_id\":\"$session_id\"}"
  fi
  printf '%s' "$payload" | bash "$_ab_events_hook" 2>/dev/null || true
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
    _prev_sig="$_baseline_sig"

    while sleep "$interval"; do
      _cur_diff="$(git diff HEAD 2>/dev/null)"
      _cur_sig="$(printf '%s' "$_cur_diff" | shasum 2>/dev/null | awk '{print $1}')"
      [[ -z "$_cur_sig" ]] && _cur_sig="-"
      [[ "$_cur_sig" == "$_prev_sig" ]] && continue

      # Log every currently-modified tracked file. Safe to over-report: a
      # duplicate event on a file that was already logged is a no-op for
      # handoff context, and the diff-content hash guard above keeps this
      # loop from firing unless actual content changed.
      _changed="$(git diff --name-only HEAD 2>/dev/null | sort -u)"
      while IFS= read -r _f; do
        [[ -n "$_f" ]] || continue
        _payload="{\"hook_event_name\":\"FileChange\",\"session_id\":\"$session_id\",\"tool_name\":\"_observed_edit\",\"file_path\":\"$_f\"}"
        # AGENTBOARD_PROVIDER must be set for the *hook* process (right side
        # of the pipe) — setting it on the printf is a no-op for the hook.
        printf '%s' "$_payload" | AGENTBOARD_PROVIDER="$_provider_env" bash "$_hook" 2>/dev/null || true
      done <<< "$_changed"

      _prev_sig="$_cur_sig"
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
