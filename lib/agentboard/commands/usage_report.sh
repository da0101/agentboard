# Usage monitoring — read-only reports: stream, summary, history, optimize

# Called only from cmd_usage, which provides $db, $has_note and
# $has_task_complexity in scope.
_usage_stream_cmd() {
  local target_stream="${1:-}"
  [[ -n "$target_stream" ]] || die "Usage: ab usage stream <stream-slug>"
  local complexity_select_stream="task_complexity AS Complexity"
  local complexity_group_stream="COALESCE(task_complexity,'—') AS Complexity"
  local complexity_group_by_stream="task_complexity"
  local note_select_stream="note AS Note"
  if (( ! has_task_complexity )); then
    complexity_select_stream="'—' AS Complexity"
    complexity_group_stream="'—' AS Complexity"
    complexity_group_by_stream="'—'"
  fi
  if (( ! has_note )); then
    note_select_stream="'' AS Note"
  fi
  printf '\n%s%sStream: %s%s\n\n' "$C_BOLD" "$C_CYAN" "$target_stream" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT timestamp, agent_provider AS Provider, model AS Model,
           task_type AS Type, ${complexity_select_stream},
           input_tokens AS Input, output_tokens AS Output,
           total_tokens AS Total, ${note_select_stream}
    FROM usage WHERE stream_slug = '$target_stream' ORDER BY timestamp ASC;
  "
  say
  sqlite3 -header -column "$db" "
    SELECT task_type AS Type, ${complexity_group_stream},
           COUNT(*) AS Segments, SUM(total_tokens) AS Total
    FROM usage WHERE stream_slug = '$target_stream'
    GROUP BY task_type, ${complexity_group_by_stream} ORDER BY Total DESC;
  "
  say
  sqlite3 -header -column "$db" "
    SELECT agent_provider AS Provider, model AS Model,
           COUNT(*) AS Segments,
           SUM(input_tokens) AS Total_Input, SUM(output_tokens) AS Total_Output,
           SUM(total_tokens) AS Grand_Total
    FROM usage WHERE stream_slug = '$target_stream'
    GROUP BY agent_provider, model ORDER BY Grand_Total DESC;
  "
  say
  sqlite3 "$db" "
    SELECT '  STREAM TOTAL: ' || SUM(total_tokens) || ' tokens across '
           || COUNT(*) || ' context segment(s)'
    FROM usage WHERE stream_slug = '$target_stream';
  "
}

_usage_summary_cmd() {
  local complexity_select_summary="COALESCE(task_complexity,'—') AS Complexity"
  local complexity_group_by_summary="task_complexity"
  if (( ! has_task_complexity )); then
    complexity_select_summary="'—' AS Complexity"
    complexity_group_by_summary="'—'"
  fi
  printf '\n%s%sGlobal Token Usage — Last 30 Days%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT agent_provider AS Provider, model AS Model,
           SUM(total_tokens) AS Total_Tokens, COUNT(*) AS Segments,
           CAST(SUM(total_tokens) AS REAL) / COUNT(*) AS Avg_Per_Segment
    FROM usage WHERE timestamp > date('now', '-30 days')
    GROUP BY agent_provider, model ORDER BY Total_Tokens DESC;
  "
  say
  printf '%sBy Repository:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT repo AS Repository, SUM(total_tokens) AS Total, COUNT(*) AS Segments
    FROM usage WHERE timestamp > date('now', '-30 days')
    GROUP BY repo ORDER BY Total DESC;
  "
  say
  printf '%sBy Task Type:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT task_type AS Type, SUM(total_tokens) AS Total,
           AVG(total_tokens) AS Avg_Per_Segment, COUNT(*) AS Segments
    FROM usage WHERE timestamp > date('now', '-30 days')
    GROUP BY task_type ORDER BY Total DESC;
  "
  say
  printf '%sBy Complexity:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT ${complexity_select_summary}, SUM(total_tokens) AS Total,
           AVG(total_tokens) AS Avg_Per_Segment, COUNT(*) AS Segments
    FROM usage WHERE timestamp > date('now', '-30 days')
    GROUP BY ${complexity_group_by_summary} ORDER BY Total DESC;
  "
}

_usage_history_cmd() {
  local complexity_select_history="task_complexity"
  local note_select_history="note"
  if (( ! has_task_complexity )); then
    complexity_select_history="'' AS task_complexity"
  fi
  if (( ! has_note )); then
    note_select_history="'' AS note"
  fi
  sqlite3 -header -column "$db" \
    "SELECT timestamp, repo, agent_provider, model, task_type, ${complexity_select_history}, stream_slug, total_tokens, ${note_select_history}
     FROM usage ORDER BY timestamp DESC LIMIT 20;"
}

_usage_optimize_cmd() {
  local complexity_select_optimize="COALESCE(task_complexity,'—') AS Complexity"
  if (( ! has_task_complexity )); then
    complexity_select_optimize="'—' AS Complexity"
  fi
  printf '\n%s%sOptimization Insights%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%sMost expensive task types:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT task_type AS Type, AVG(total_tokens) AS Avg_Per_Segment,
           MAX(total_tokens) AS Worst_Segment, COUNT(*) AS Segments
    FROM usage GROUP BY task_type ORDER BY Avg_Per_Segment DESC;
  "
  say
  printf '%sMost expensive streams (all providers + clears combined):%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT stream_slug AS Stream, SUM(total_tokens) AS Total,
           COUNT(DISTINCT agent_provider) AS Providers, COUNT(*) AS Segments
    FROM usage WHERE stream_slug IS NOT NULL AND stream_slug != ''
    GROUP BY stream_slug ORDER BY Total DESC LIMIT 10;
  "
  say
  printf '%sProvider efficiency comparison:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT agent_provider AS Provider, model AS Model,
           AVG(total_tokens) AS Avg_Per_Segment,
           SUM(total_tokens) AS Total, COUNT(*) AS Segments
    FROM usage GROUP BY agent_provider, model ORDER BY Avg_Per_Segment DESC;
  "
  say
  printf '%sLargest individual segments:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT timestamp, COALESCE(stream_slug,'—') AS Stream,
           COALESCE(task_type,'—') AS Type,
           ${complexity_select_optimize},
           agent_provider AS Provider, model AS Model,
           total_tokens AS Total
    FROM usage
    WHERE total_tokens > 0
    ORDER BY total_tokens DESC LIMIT 10;
  "
  say
  printf '%sStreams that need finer checkpointing:%s\n' "$C_DIM" "$C_RESET"
  sqlite3 -header -column "$db" "
    SELECT stream_slug AS Stream, COUNT(*) AS Segments,
           SUM(total_tokens) AS Total, MAX(total_tokens) AS Largest_Segment
    FROM usage
    WHERE stream_slug IS NOT NULL AND stream_slug != ''
    GROUP BY stream_slug
    HAVING SUM(total_tokens) >= 200000 AND COUNT(*) <= 2
    ORDER BY Total DESC;
  "
}
