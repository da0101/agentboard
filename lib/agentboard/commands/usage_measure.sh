# -----------------------------------------------------------------------------
# ab usage report — measured token usage (rows written by `ab usage ingest`).
#
#   ab usage report [--days N] [--by model|repo|day|provider|session] [--cost]
#
# Columns: fresh input, cache reads, cache writes, output, total, and Cache% =
# cache reads / all input. Cost is computed only from prices YOU provide in
# ~/.agentboard/pricing.tsv (override: AGENTBOARD_PRICING) — Agentboard ships no
# price table, because stale prices are worse than none:
#   <model-prefix> <TAB> input <TAB> output <TAB> cache_read <TAB> cache_write   ($ per 1M tokens)
# Called only from cmd_usage, which provides $_usage_db.
# -----------------------------------------------------------------------------

_usage_report_cmd() {
  local days=30 by="model" cost=0 dim label where total_rows
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days) days="${2:-}"; [[ "$days" =~ ^[0-9]+$ ]] || die "--days needs a number"; shift 2 ;;
      --by)   by="${2:-}"; shift 2 ;;
      --cost) cost=1; shift ;;
      -h|--help)
        say "Usage: ab usage report [--days N] [--by model|repo|day|provider|session] [--cost]"
        say "Run 'ab usage ingest' first to load real token counts from Claude/Codex transcripts."
        return 0 ;;
      *) die "Unknown flag for usage report: $1" ;;
    esac
  done
  case "$by" in
    model)    dim="model";            label="Model" ;;
    repo)     dim="COALESCE(repo,'—')"; label="Repo" ;;
    day)      dim="day";              label="Day" ;;
    provider) dim="agent_provider";   label="Provider" ;;
    session)  dim="substr(session_id,1,8)"; label="Session" ;;
    *) die "--by must be model, repo, day, provider or session" ;;
  esac
  where="source = 'ingest' AND day >= date('now', '-${days} day')"
  total_rows="$(sqlite3 "$_usage_db" "SELECT COUNT(*) FROM usage WHERE $where;")"
  if (( total_rows == 0 )); then
    say "No measured usage in the last ${days} days. Run: ab usage ingest [--all]"
    return 0
  fi

  printf '\n%s%sMeasured token usage — last %s days, by %s%s\n\n' "$C_BOLD" "$C_CYAN" "$days" "$by" "$C_RESET"
  sqlite3 -header -column "$_usage_db" "
    SELECT ${dim} AS ${label},
           COUNT(DISTINCT session_id) AS Sessions,
           printf('%.2fM', SUM(input_tokens) / 1e6)       AS FreshIn,
           printf('%.2fM', SUM(cache_read_tokens) / 1e6)  AS CacheRead,
           printf('%.2fM', SUM(cache_write_tokens) / 1e6) AS CacheWrite,
           printf('%.2fM', SUM(output_tokens) / 1e6)      AS Output,
           printf('%.2fM', SUM(total_tokens) / 1e6)       AS Total,
           printf('%.1f%%', 100.0 * SUM(cache_read_tokens) /
                  NULLIF(SUM(input_tokens + cache_read_tokens + cache_write_tokens), 0)) AS 'Cache%'
    FROM usage WHERE $where GROUP BY 1 ORDER BY SUM(total_tokens) DESC;"
  printf '\n'
  sqlite3 "$_usage_db" "
    SELECT printf('  Overall: %.2fM tokens across %d sessions; cache reads are %.1f%% of all input; output is %.1f%% of total.',
           SUM(total_tokens) / 1e6, COUNT(DISTINCT session_id),
           100.0 * SUM(cache_read_tokens) / NULLIF(SUM(input_tokens + cache_read_tokens + cache_write_tokens), 0),
           100.0 * SUM(output_tokens) / NULLIF(SUM(total_tokens), 0))
    FROM usage WHERE $where;"
  sqlite3 "$_usage_db" "
    SELECT printf('  Largest session: %s (%s, %.2fM tokens)', substr(session_id,1,8), agent_provider, SUM(total_tokens) / 1e6)
    FROM usage WHERE $where GROUP BY session_id, agent_provider ORDER BY SUM(total_tokens) DESC LIMIT 1;"
  (( cost )) && _usage_report_cost "$where"
  printf '\n'
  return 0
}

_usage_report_cost() {
  local where="$1" prices="${AGENTBOARD_PRICING:-$HOME/.agentboard/pricing.tsv}"
  if [[ ! -f "$prices" ]]; then
    printf '\n  No prices configured, so no cost is shown (Agentboard ships no price table).\n'
    printf '  Create %s with one line per model prefix, tab-separated, $ per 1M tokens:\n' "$prices"
    printf '    <model-prefix>\\t<input>\\t<output>\\t<cache_read>\\t<cache_write>\n'
    return 0
  fi
  printf '\n  %sEstimated cost (your prices in %s)%s\n' "$C_BOLD" "$prices" "$C_RESET"
  sqlite3 -separator $'\t' "$_usage_db" "
    SELECT model, SUM(input_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens), SUM(output_tokens)
    FROM usage WHERE $where GROUP BY model;" |
  awk -F'\t' -v pf="$prices" '
    BEGIN { while ((getline line < pf) > 0) { if (line ~ /^#/ || line == "") continue
              n = split(line, f, "\t"); if (n >= 5) { P[f[1]] = 1; PI[f[1]] = f[2]; PO[f[1]] = f[3]; PR[f[1]] = f[4]; PW[f[1]] = f[5] } } }
    { best = ""; for (p in P) if (index($1, p) == 1 && length(p) > length(best)) best = p
      if (best == "") { printf "    %-28s no price for this model\n", $1; unknown++; next }
      c = ($2 * PI[best] + $3 * PR[best] + $4 * PW[best] + $5 * PO[best]) / 1e6; tot += c
      printf "    %-28s $%.2f\n", $1, c }
    END { printf "    %-28s $%.2f%s\n", "TOTAL (priced models)", tot, (unknown ? "  (+ " unknown " unpriced)" : "") }'
}
