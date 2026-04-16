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
        session_id TEXT
    );"
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
      local provider="" model="" stream="" input=0 output=0 repo="" type="chore"
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
          *) shift ;;
        esac
      done
      [[ -n "$provider" ]] || die "Usage: agentboard usage log --provider <name> --input <N> --output <N> [--model <M>] [--stream <S>] [--repo <R>] [--type <T>]"

      local total=$((input + output))
      sqlite3 "$db" "INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens)
        VALUES ('$provider', '$model', '$stream', '$repo', '$type', $input, $output, $total);"
      ok "Logged $total tokens to ~/.agentboard/usage.db  (provider=$provider, repo=$repo, type=$type)"
      ;;

    summary)
      printf '\n%s%sGlobal Token Usage — Last 30 Days%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          agent_provider  AS Provider,
          model           AS Model,
          SUM(total_tokens) AS Total_Tokens,
          COUNT(*)          AS Turns,
          CAST(SUM(total_tokens) AS REAL) / COUNT(*) AS Avg_Per_Turn
        FROM usage
        WHERE timestamp > date('now', '-30 days')
        GROUP BY agent_provider, model
        ORDER BY Total_Tokens DESC;
      "
      say
      printf '%sBy Repository:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT repo AS Repository, SUM(total_tokens) AS Total, COUNT(*) AS Turns
        FROM usage
        WHERE timestamp > date('now', '-30 days')
        GROUP BY repo ORDER BY Total DESC;
      "
      say
      printf '%sBy Task Type:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT task_type AS Type, AVG(total_tokens) AS Avg_Tokens, COUNT(*) AS Frequency
        FROM usage
        GROUP BY task_type ORDER BY Avg_Tokens DESC;
      "
      ;;

    history)
      sqlite3 -header -column "$db" \
        "SELECT timestamp, repo, agent_provider, model, task_type, stream_slug, total_tokens
         FROM usage ORDER BY timestamp DESC LIMIT 20;"
      ;;

    optimize)
      printf '\n%s%sOptimization Insights%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT
          task_type  AS Type,
          AVG(total_tokens) AS Avg_Tokens,
          MAX(total_tokens) AS Peak_Turn,
          COUNT(*)          AS Frequency
        FROM usage
        GROUP BY task_type ORDER BY Avg_Tokens DESC;
      "
      say
      printf '%sHint: If research tasks average >50 k tokens, switch to targeted line reads (file:L10-50) instead of full-file reads.%s\n' "$C_DIM" "$C_RESET"
      ;;

    *)
      die "Unknown usage subcommand: $sub. Options: summary | log | history | optimize"
      ;;
  esac
}
