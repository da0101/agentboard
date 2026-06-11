# Usage monitoring — SQLite-backed token tracking across all projects

_usage_db="$HOME/.ab/usage.db"

_init_usage_db() {
  if [[ ! -f "$_usage_db" ]]; then
    mkdir -p "$HOME/.ab"
    sqlite3 "$_usage_db" "CREATE TABLE IF NOT EXISTS usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        agent_provider TEXT NOT NULL,
        model TEXT,
        stream_slug TEXT,
        repo TEXT,
        task_type TEXT,
        task_complexity TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        total_tokens INTEGER,
        estimated_cost REAL,
        note TEXT,
        session_id TEXT
    );"
  else
    sqlite3 "$_usage_db" \
      "ALTER TABLE usage ADD COLUMN note TEXT;" 2>/dev/null || true
    sqlite3 "$_usage_db" \
      "ALTER TABLE usage ADD COLUMN task_complexity TEXT;" 2>/dev/null || true
  fi
}

# Sum a column for rows matching a session key.
# Session key format: "<stream>|<provider>|<YYYY-MM-DD>". Rows are matched by
# stream_slug + agent_provider + calendar day (DATE(timestamp) in local zone).
_usage_session_sum() {
  local db="$1" key="$2" column="$3"
  # Parse key (fields separated by |)
  local stream provider day
  stream="$(printf '%s' "$key" | awk -F'|' '{print $1}')"
  provider="$(printf '%s' "$key" | awk -F'|' '{print $2}')"
  day="$(printf '%s' "$key" | awk -F'|' '{print $3}')"
  # Empty day means caller gave non-standard session key; fall back to matching
  # the key exactly on stream_slug + provider with any timestamp.
  local _s="${stream//\'/\'\'}" _p="${provider//\'/\'\'}" _d="${day//\'/\'\'}"
  if [[ -z "$day" ]]; then
    sqlite3 "$db" "SELECT COALESCE(SUM($column), 0) FROM usage
      WHERE stream_slug = '$_s' AND agent_provider = '$_p';"
    return 0
  fi
  sqlite3 "$db" "SELECT COALESCE(SUM($column), 0) FROM usage
    WHERE stream_slug = '$_s'
      AND agent_provider = '$_p'
      AND DATE(timestamp, 'localtime') = '$_d';"
}

_usage_has_column() {
  local db="$1" column="$2"
  sqlite3 "$db" "PRAGMA table_info(usage);" 2>/dev/null \
    | awk -F'|' -v target="$column" '$2 == target { found = 1 } END { exit(found ? 0 : 1) }'
}

cmd_usage() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required for usage monitoring. Install it first."

  _init_usage_db
  local db="$_usage_db"
  local has_note=0 has_task_complexity=0
  _usage_has_column "$db" "note" && has_note=1 || true
  _usage_has_column "$db" "task_complexity" && has_task_complexity=1 || true
  local sub="${1:-summary}"
  shift || true

  case "$sub" in
    log)       _usage_log_cmd "$@" ;;
    stream)    _usage_stream_cmd "$@" ;;
    summary)   _usage_summary_cmd "$@" ;;
    history)   _usage_history_cmd "$@" ;;
    optimize)  _usage_optimize_cmd "$@" ;;
    learn)     _usage_learn_cmd "$@" ;;
    dashboard) _usage_dashboard_cmd "$@" ;;
    *)
      die "Unknown usage subcommand: $sub. Options: summary | log | stream <slug> | history | optimize | learn [--apply] | dashboard [--today|--week|--month]"
      ;;
  esac
}
