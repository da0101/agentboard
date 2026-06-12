# -----------------------------------------------------------------------------
# Advisory file locking for concurrent .platform/ state writes.
#
# Pure bash + file I/O — mkdir-based lock dirs (mkdir is atomic on POSIX) under
# .platform/.locks/<name>.lock/. Distinct from the daemon's HTTP per-file lock
# concept (bin/ab-daemon.js, `ab lock` — provider coordination): these locks
# guard the CLI's own read-modify-write sequences on shared state files
# (ACTIVE.md, stream files, events.jsonl) against concurrent ab processes,
# e.g. `ab watch --once` racing `ab checkpoint`.
#
# Semantics:
#   - Advisory only. Callers fail OPEN: if a lock can't be acquired within the
#     timeout, platform_lock_acquire warns and returns 1 — single-user UX never
#     hard-blocks. Call sites use `platform_lock_acquire <name> || true`.
#   - Stale locks are stolen when the recorded holder pid is dead (kill -0),
#     or when the lock is older than PLATFORM_LOCK_STALE_SECS (~60s). Age uses
#     a written epoch timestamp — no GNU stat flags, portable everywhere.
#   - The holder pid is $$ recorded at acquire time (never $PPID — subshells
#     change it). Ownership for release is a per-acquire token, so a process
#     that failed to acquire (fail-open path) can never remove someone else's
#     lock by calling release.
# -----------------------------------------------------------------------------

PLATFORM_LOCKS_ROOT="./.platform/.locks"
PLATFORM_LOCK_STALE_SECS="${AGENTBOARD_LOCK_STALE_SECS:-60}"
PLATFORM_LOCK_TIMEOUT_SECS="${AGENTBOARD_LOCK_TIMEOUT_SECS:-5}"
PLATFORM_LOCK_POLL_SLEEP="0.1"

_platform_lock_path() {
  printf '%s/%s.lock' "$PLATFORM_LOCKS_ROOT" "$1"
}

# In-shell ownership token storage. One scalar var per lock name — no
# associative arrays (bash 3.2). Background subshells inherit a copy, so each
# acquirer tracks its own token independently.
_platform_lock_token_var() {
  local name="$1"
  printf '__PLATFORM_LOCK_TOKEN_%s' "${name//[^a-zA-Z0-9]/_}"
}

# True (0) when the lock dir looks abandoned and may be stolen.
_platform_lock_is_stale() {
  local lock="$1" pid acquired now
  [[ -d "$lock" ]] || return 1

  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0  # recorded holder is dead
    fi
  fi

  acquired="$(cat "$lock/acquired_at" 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ "$acquired" =~ ^[0-9]+$ ]]; then
    (( now - acquired >= PLATFORM_LOCK_STALE_SECS )) && return 0
    return 1
  fi

  # No readable metadata (partial create, foreign writer). Steal only if the
  # dir itself is old — portable mtime check via find, no GNU stat flags.
  [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]]
}

# Remove a stale lock dir race-safely: rename first (atomic — only one stealer
# wins the mv), then delete the renamed dir. Losers simply loop and retry.
_platform_lock_steal() {
  local lock="$1" trash
  trash="${lock}.stale.$$.${RANDOM}"
  if mv "$lock" "$trash" 2>/dev/null; then
    rm -rf "$trash" 2>/dev/null || true
  fi
  return 0
}

# platform_lock_acquire <name> [timeout_s]
# Retry loop with short sleeps until the lock dir is created or the timeout
# expires. Returns 0 when held; warns and returns 1 on timeout (fail open).
platform_lock_acquire() {
  local name="${1:-}" timeout="${2:-$PLATFORM_LOCK_TIMEOUT_SECS}"
  [[ -n "$name" ]] || { warn "platform_lock_acquire: missing lock name"; return 1; }
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout="$PLATFORM_LOCK_TIMEOUT_SECS"

  local lock token deadline var
  lock="$(_platform_lock_path "$name")"
  var="$(_platform_lock_token_var "$name")"
  token="${BASHPID:-$$}.${RANDOM}.$(date +%s)"
  deadline=$(( $(date +%s) + timeout ))

  if ! mkdir -p "$PLATFORM_LOCKS_ROOT" 2>/dev/null; then
    warn "Could not create $PLATFORM_LOCKS_ROOT — proceeding without lock '$name'"
    return 1
  fi

  while :; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s\n' "$$" > "$lock/pid" 2>/dev/null || true
      printf '%s\n' "$(date +%s)" > "$lock/acquired_at" 2>/dev/null || true
      printf '%s\n' "$token" > "$lock/token" 2>/dev/null || true
      printf -v "$var" '%s' "$token"
      return 0
    fi
    if _platform_lock_is_stale "$lock"; then
      _platform_lock_steal "$lock"
      continue
    fi
    if (( $(date +%s) >= deadline )); then
      break
    fi
    sleep "$PLATFORM_LOCK_POLL_SLEEP"
  done

  warn "Could not acquire lock '$name' within ${timeout}s — proceeding without it"
  return 1
}

# platform_lock_release <name>
# Removes the lock only if this shell holds it (token match). Always returns 0
# so release is safe on fail-open paths and in set -e contexts.
platform_lock_release() {
  local name="${1:-}"
  [[ -n "$name" ]] || return 0

  local lock var mine recorded
  lock="$(_platform_lock_path "$name")"
  var="$(_platform_lock_token_var "$name")"
  mine="${!var:-}"
  [[ -n "$mine" ]] || return 0
  [[ -d "$lock" ]] || { printf -v "$var" '%s' ""; return 0; }

  recorded="$(cat "$lock/token" 2>/dev/null || true)"
  if [[ "$recorded" == "$mine" ]]; then
    rm -rf "$lock" 2>/dev/null || true
  fi
  printf -v "$var" '%s' ""
  return 0
}

# platform_with_lock <name> <command> [args...]
# Runs the command under the named lock with the default timeout. Fails open:
# if the lock can't be acquired, the command still runs (acquire already
# warned). Returns the command's exit status.
platform_with_lock() {
  local name="${1:-}"
  shift || true
  local locked=0 status=0
  if platform_lock_acquire "$name"; then
    locked=1
  fi
  "$@" || status=$?
  if (( locked )); then
    platform_lock_release "$name"
  fi
  return "$status"
}
