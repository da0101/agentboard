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
    sqlite3 "$_usage_db" \
      "ALTER TABLE usage ADD COLUMN note TEXT;" 2>/dev/null || true
  fi
}

# Emit a learning entry as a markdown bullet for .platform/learnings.md
_learning_entry() {
  local date today
  today="$(date +%Y-%m-%d)"
  printf '- [%s] [token-optimization] %s\n' "$today" "$1"
}

# Analyse patterns and emit findings + recommendations
# Returns lines of the form: FINDING|RECOMMENDATION|SAVING
_analyse_patterns() {
  local db="$1"

  # ── Model overkill: Opus used for cheap tasks ──────────────────────────────
  # Threshold: opus segments averaging < 20k tokens  (≥3 samples)
  while IFS='|' read -r task_type avg_tokens segments; do
    [[ -z "$task_type" ]] && continue
    printf 'MODEL_OVERKILL|%s|%.0f|%s\n' "$task_type" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT task_type, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE model LIKE '%opus%' AND total_tokens > 0
    GROUP BY task_type
    HAVING n >= 3 AND avg < 20000
    ORDER BY avg ASC;
  ")

  # ── Research bloat: research tasks averaging > 60k ────────────────────────
  while IFS='|' read -r repo avg_tokens segments; do
    [[ -z "$repo" ]] && continue
    printf 'RESEARCH_BLOAT|%s|%.0f|%s\n' "$repo" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT repo, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE task_type = 'research' AND total_tokens > 0
    GROUP BY repo
    HAVING n >= 3 AND avg > 60000
    ORDER BY avg DESC;
  ")

  # ── Debug drain: debug tasks averaging > 80k ──────────────────────────────
  while IFS='|' read -r repo avg_tokens segments; do
    [[ -z "$repo" ]] && continue
    printf 'DEBUG_DRAIN|%s|%.0f|%s\n' "$repo" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT repo, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE task_type = 'debug' AND total_tokens > 0
    GROUP BY repo
    HAVING n >= 3 AND avg > 80000
    ORDER BY avg DESC;
  ")

  # ── Hot repo: one repo consuming >60% of total tokens ─────────────────────
  while IFS='|' read -r repo repo_total global_pct; do
    [[ -z "$repo" ]] && continue
    printf 'HOT_REPO|%s|%s|%.0f\n' "$repo" "$repo_total" "$global_pct"
  done < <(sqlite3 "$db" "
    SELECT repo,
           SUM(total_tokens) AS repo_total,
           100.0 * SUM(total_tokens) / (SELECT SUM(total_tokens) FROM usage) AS pct
    FROM usage
    WHERE total_tokens > 0
    GROUP BY repo
    HAVING pct > 60
    ORDER BY repo_total DESC
    LIMIT 1;
  ")

  # ── Context thrash: stream with >4 segments ───────────────────────────────
  while IFS='|' read -r stream segments total; do
    [[ -z "$stream" ]] && continue
    printf 'CONTEXT_THRASH|%s|%s|%s\n' "$stream" "$segments" "$total"
  done < <(sqlite3 "$db" "
    SELECT stream_slug, COUNT(*) AS n, SUM(total_tokens) AS total
    FROM usage
    WHERE stream_slug IS NOT NULL AND stream_slug != '' AND total_tokens > 0
    GROUP BY stream_slug
    HAVING n > 4
    ORDER BY n DESC
    LIMIT 5;
  ")
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
        SELECT timestamp, agent_provider AS Provider, model AS Model,
               input_tokens AS Input, output_tokens AS Output,
               total_tokens AS Total, note AS Note
        FROM usage WHERE stream_slug = '$target_stream' ORDER BY timestamp ASC;
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
      ;;

    summary)
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
      ;;

    history)
      sqlite3 -header -column "$db" \
        "SELECT timestamp, repo, agent_provider, model, task_type, stream_slug, total_tokens, note
         FROM usage ORDER BY timestamp DESC LIMIT 20;"
      ;;

    optimize)
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
      ;;

    learn)
      local apply=0 learnings_file="./.platform/learnings.md"
      [[ "${1:-}" == "--apply" ]] && apply=1

      printf '\n%s%sUsage Learning Analysis%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

      local total_rows
      total_rows="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE total_tokens > 0;")"
      if [[ "$total_rows" -lt 5 ]]; then
        warn "Not enough data yet ($total_rows segments logged). Need at least 5 to generate learnings."
        say
        printf '%sKeep logging with: agentboard usage log --provider ... --input ... --output ...%s\n' "$C_DIM" "$C_RESET"
        return 0
      fi

      local findings=() recommendations=() new_learnings=()
      local kind a b c

      while IFS='|' read -r kind a b c; do
        case "$kind" in
          MODEL_OVERKILL)
            local task_type="$a" avg="$b" segs="$c"
            local rec="Use Sonnet (or Haiku for tasks <5k tokens) instead of Opus for '${task_type}' tasks — avg ${avg} tokens over ${segs} segments is below Opus's value threshold."
            local learning="Opus is over-specified for '${task_type}' tasks (avg ${avg} tokens, ${segs} samples). Default to claude-sonnet-4-6 for this task type."
            printf '  %s⚠ MODEL_OVERKILL%s  %s tasks — Opus averaging %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$task_type" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          RESEARCH_BLOAT)
            local repo="$a" avg="$b" segs="$c"
            local rec="In '${repo}': research tasks avg ${avg} tokens. Use targeted reads (grep/glob + line ranges) instead of full-file reads. Load only files listed in work/BRIEF.md § Relevant context."
            local learning="Research tasks in '${repo}' are expensive (avg ${avg} tokens, ${segs} samples). Enforce scoped context loading: read only files listed in BRIEF.md, use line-range reads."
            printf '  %s⚠ RESEARCH_BLOAT%s  %s — research avg %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          DEBUG_DRAIN)
            local repo="$a" avg="$b" segs="$c"
            local rec="In '${repo}': debug tasks avg ${avg} tokens. Run /ab-debug (hypothesis-first, max 3 reads before testing) rather than broad exploration."
            local learning="Debug sessions in '${repo}' are expensive (avg ${avg} tokens, ${segs} samples). Enforce hypothesis-first debugging: state hypothesis, read ≤3 files, test, iterate."
            printf '  %s⚠ DEBUG_DRAIN%s  %s — debug avg %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          HOT_REPO)
            local repo="$a" total="$b" pct="$c"
            local rec="'${repo}' is consuming ${pct}% of all tokens. Check conventions/ for that repo — context may be loading too many files at session start."
            local learning="'${repo}' dominates token spend (${pct}% of total). Audit session start context loading — reduce files loaded by default in ONBOARDING.md or BRIEF.md."
            printf '  %s⚠ HOT_REPO%s  %s — %s%% of all token spend (%s total tokens)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$pct" "$total"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          CONTEXT_THRASH)
            local stream="$a" segs="$b" total="$c"
            local rec="Stream '${stream}' needed ${segs} context clears (${total} total tokens). Break this type of work into smaller focused streams, or load less context per session."
            local learning="Stream '${stream}' required ${segs} context resets (${total} tokens total). For similar tasks: pre-scope the domain, load only 1-2 reference files, keep stream focused."
            printf '  %s⚠ CONTEXT_THRASH%s  %s — %s context segments, %s total tokens\n' \
              "$C_YELLOW" "$C_RESET" "$stream" "$segs" "$total"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
        esac
      done < <(_analyse_patterns "$db")

      if [[ ${#new_learnings[@]} -eq 0 ]]; then
        ok "No significant inefficiencies detected in current data."
        say
        printf '%sRun again after more sessions are logged.%s\n' "$C_DIM" "$C_RESET"
        return 0
      fi

      printf '%s%d finding(s) detected.%s\n' "$C_BOLD" "${#new_learnings[@]}" "$C_RESET"

      if (( apply )); then
        if [[ ! -f "$learnings_file" ]]; then
          warn "No .platform/learnings.md found in current directory. Run from inside a project."
          return 1
        fi
        say
        local entry
        for entry in "${new_learnings[@]}"; do
          local line; line="$(_learning_entry "$entry")"
          # Only append if not already present (dedup by content)
          if ! grep -qF "$entry" "$learnings_file"; then
            printf '%s\n' "$line" >> "$learnings_file"
            ok "Written to learnings.md: ${entry:0:80}..."
          else
            printf '  %s↷%s Already in learnings.md — skipped\n' "$C_DIM" "$C_RESET"
          fi
        done
        say
        ok "learnings.md updated. The LLM will apply these rules at the next session start."
      else
        say
        printf '%sRun with --apply to write these findings to .platform/learnings.md%s\n' \
          "$C_DIM" "$C_RESET"
        printf '%sThe LLM reads learnings.md at session start and adjusts its behaviour.%s\n' \
          "$C_DIM" "$C_RESET"
      fi
      ;;

    *)
      die "Unknown usage subcommand: $sub. Options: summary | log | stream <slug> | history | optimize | learn [--apply]"
      ;;
  esac
}
