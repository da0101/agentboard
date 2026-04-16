# Usage monitoring — SQLite-backed token tracking across all projects

_usage_db="$HOME/.agentboard/usage.db"

_init_usage_db() {
  if [[ ! -f "$_usage_db" ]]; then
    mkdir -p "$HOME/.agentboard"
    sqlite3 "$_usage_db" "CREATE TABLE IF NOT EXISTS usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        agent_provider TEXT NOT NULL,
        model TEXT,
        stream_slug TEXT,
        repo TEXT,
        task_type TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        total_tokens INTEGER,
        estimated_cost REAL,
        note TEXT,
        session_id TEXT
    );"
  else
    # Add note column to existing databases that predate this field
    sqlite3 "$_usage_db" \
      "ALTER TABLE usage ADD COLUMN note TEXT;" 2>/dev/null || true
  fi
}

cmd_usage() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required for usage monitoring. Install it first."

  _init_usage_db
  local db="$_usage_db"
  local sub="${1:-summary}"
  shift || true

  case "$sub" in
    log)
      local provider="" model="" stream="" input=0 output=0 repo="" type="chore" note=""
      repo="$(basename "$(pwd)")"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --provider) provider="$2"; shift 2 ;;
          --model)    model="$2";    shift 2 ;;
          --stream)   stream="$2";   shift 2 ;;
          --repo)     repo="$2";     shift 2 ;;
          --type)     type="$2";     shift 2 ;;
          --input)    input="$2";    shift 2 ;;
          --output)   output="$2";   shift 2 ;;
          --note)     note="$2";     shift 2 ;;
          *) shift ;;
        esac
      done
      [[ -n "$provider" ]] || die "Usage: agentboard usage log --provider <name> --input <N> --output <N> [--model <M>] [--stream <S>] [--repo <R>] [--type <T>] [--note <text>]"

      local total=$((input + output))
      sqlite3 "$db" "INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens, note)
        VALUES ('$provider', '$model', '$stream', '$repo', '$type', $input, $output, $total, '$note');"
      ok "Logged $total tokens  (provider=$provider repo=$repo stream=${stream:-none} type=$type)"
      [[ -n "$note" ]] && printf '  note: %s\n' "$note"
      ;;

    stream)
      local target_stream="${1:-}"
      [[ -n "$target_stream" ]] || die "Usage: agentboard usage stream <stream-slug>"
      printf '\n%s%sStream: %s%s\n\n' "$C_BOLD" "$C_CYAN" "$target_stream" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          timestamp,
          agent_provider  AS Provider,
          model           AS Model,
          input_tokens    AS Input,
          output_tokens   AS Output,
          total_tokens    AS Total,
          note            AS Note
        FROM usage
        WHERE stream_slug = '$target_stream'
        ORDER BY timestamp ASC;
      "
      say
      sqlite3 -header -column "$db" "
        SELECT
          agent_provider  AS Provider,
          model           AS Model,
          COUNT(*)        AS Segments,
          SUM(input_tokens)  AS Total_Input,
          SUM(output_tokens) AS Total_Output,
          SUM(total_tokens)  AS Grand_Total
        FROM usage
        WHERE stream_slug = '$target_stream'
        GROUP BY agent_provider, model
        ORDER BY Grand_Total DESC;
      "
      say
      sqlite3 "$db" "
        SELECT '  STREAM TOTAL: ' || SUM(total_tokens) || ' tokens across ' || COUNT(*) || ' context segment(s)'
        FROM usage WHERE stream_slug = '$target_stream';
      "
      ;;

    summary)
      printf '\n%s%sGlobal Token Usage — Last 30 Days%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          agent_provider  AS Provider,
          model           AS Model,
          SUM(total_tokens)  AS Total_Tokens,
          COUNT(*)           AS Segments,
          CAST(SUM(total_tokens) AS REAL) / COUNT(*) AS Avg_Per_Segment
        FROM usage
        WHERE timestamp > date('now', '-30 days')
        GROUP BY agent_provider, model
        ORDER BY Total_Tokens DESC;
      "
      say
      printf '%sBy Repository:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT repo AS Repository, SUM(total_tokens) AS Total, COUNT(*) AS Segments
        FROM usage
        WHERE timestamp > date('now', '-30 days')
        GROUP BY repo ORDER BY Total DESC;
      "
      say
      printf '%sBy Task Type:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT task_type AS Type, SUM(total_tokens) AS Total, AVG(total_tokens) AS Avg_Per_Segment, COUNT(*) AS Segments
        FROM usage
        WHERE timestamp > date('now', '-30 days')
        GROUP BY task_type ORDER BY Total DESC;
      "
      ;;

    history)
      sqlite3 -header -column "$db" \
        "SELECT timestamp, repo, agent_provider, model, task_type, stream_slug, total_tokens, note
         FROM usage ORDER BY timestamp DESC LIMIT 20;"
      ;;

    optimize)
      printf '\n%s%sOptimization Insights%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      printf '%sMost expensive task types (avg tokens per context segment):%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          task_type  AS Type,
          AVG(total_tokens) AS Avg_Per_Segment,
          MAX(total_tokens) AS Worst_Segment,
          COUNT(*)          AS Segments
        FROM usage
        GROUP BY task_type ORDER BY Avg_Per_Segment DESC;
      "
      say
      printf '%sMost expensive streams (total across all providers + clears):%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          stream_slug AS Stream,
          SUM(total_tokens) AS Total,
          COUNT(DISTINCT agent_provider) AS Providers,
          COUNT(*) AS Segments
        FROM usage
        WHERE stream_slug IS NOT NULL AND stream_slug != ''
        GROUP BY stream_slug ORDER BY Total DESC LIMIT 10;
      "
      say
      printf '%sProvider comparison (same streams, different providers):%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT agent_provider AS Provider, AVG(total_tokens) AS Avg_Per_Segment,
               SUM(total_tokens) AS Total, COUNT(*) AS Segments
        FROM usage GROUP BY agent_provider ORDER BY Avg_Per_Segment DESC;
      "
      ;;

    *)
      die "Unknown usage subcommand: $sub. Options: summary | log | stream <slug> | history | optimize"
      ;;
  esac
}
