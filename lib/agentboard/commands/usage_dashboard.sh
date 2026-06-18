# Usage monitoring — `ab usage dashboard` rendering

# Called only from cmd_usage, which provides $db in scope.
_usage_dashboard_cmd() {
  local period_days=30 period_label="Last 30 Days"
  for arg in "$@"; do
    case "$arg" in
      --today) period_days=1;  period_label="Today"        ;;
      --week)  period_days=7;  period_label="Last 7 Days"  ;;
      --month) period_days=30; period_label="Last 30 Days" ;;
    esac
  done
  local where="timestamp > datetime('now', '-${period_days} days')"

  local tw; tw="$(tput cols 2>/dev/null || printf '80')"
  (( tw > 120 )) && tw=120; (( tw < 60 )) && tw=60
  local bar_w=$(( tw - 52 ))
  (( bar_w < 14 )) && bar_w=14; (( bar_w > 40 )) && bar_w=40

  _db_ktok() {
    local n="${1:-0}"
    (( n == 0 )) && { printf '%7s' '—'; return; }
    if   (( n >= 1000000 )); then printf '%4d.%dM' "$((n/1000000))" "$((n%1000000/100000))"
    elif (( n >= 1000 ));    then printf '%4d.%dk' "$((n/1000))"    "$((n%1000/100))"
    else                          printf '%7d' "$n"; fi
  }

  # _db_cbar: filled █ in $clr, empty ░ in dark gray, then reset
  # Use printf octal \033 to embed ESC reliably on bash 3.x
  _db_cbar() {
    local val="$1" max="$2" width="$3" clr="$4"
    (( max <= 0 )) && max=1
    local f=$(( val * width / max ))
    (( f > width )) && f=$width; (( f < 0 )) && f=0
    local e=$(( width - f )) fb='' eb=''
    (( f > 0 )) && fb="$(printf '%.0s█' $(seq 1 "$f"))"
    (( e > 0 )) && eb="$(printf '%.0s░' $(seq 1 "$e"))"
    printf '%s%s\033[38;5;238m%s\033[0m' "$clr" "$fb" "$eb"
  }

  # bash 3.x-safe lowercase via tr (${1,,} requires bash 4+)
  _db_pclr() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
      claude|anthropic) printf '\033[38;5;87m'  ;;
      codex|openai)     printf '\033[38;5;114m' ;;
      gemini|google)    printf '\033[38;5;220m' ;;
      *)                printf '\033[38;5;252m' ;;
    esac
  }

  # Heat colour: green (small/cheap) → yellow → orange → red (large/expensive)
  _db_heat() {
    local val="$1" max="$2"
    (( max <= 0 )) && max=1
    local pct=$(( val * 100 / max ))
    if   (( pct < 15 )); then printf '\033[38;5;82m'
    elif (( pct < 35 )); then printf '\033[38;5;148m'
    elif (( pct < 60 )); then printf '\033[38;5;214m'
    elif (( pct < 80 )); then printf '\033[38;5;208m'
    else                      printf '\033[38;5;196m'
    fi
  }

  _db_row() {
    local lbl="$1" val="$2" max="$3" clr="$4"
    (( max <= 0 )) && max=1
    local pct=$(( val * 100 / max ))
    printf '  %-22.22s  ' "$lbl"
    _db_cbar "$val" "$max" "$bar_w" "$clr"
    printf '  %s%s%s  %s%3d%%%s\n' \
      "$C_BOLD" "$(_db_ktok "$val")" "$C_RESET" "$C_DIM" "$pct" "$C_RESET"
  }

  _db_section() {
    local title="$1"
    local dashes=$(( tw - ${#title} - 4 ))
    (( dashes < 1 )) && dashes=1
    printf '\n%s%s━━ %s%s %s' "$C_BOLD" "$C_CYAN" "$title" "$C_RESET" "$C_DIM"
    (( dashes > 0 )) && printf '%.0s━' $(seq 1 "$dashes")
    printf '%s\n\n' "$C_RESET"
  }

  # ── Totals ──────────────────────────────────────────────────────────────
  local tt=0 ts=0 tp=0 tr=0
  IFS='|' read -r tt ts tp tr < <(sqlite3 "$db" \
    "SELECT COALESCE(SUM(total_tokens),0), COUNT(*),
            COUNT(DISTINCT agent_provider), COUNT(DISTINCT repo)
     FROM usage WHERE $where;") || true
  tt="${tt:-0}"; ts="${ts:-0}"; tp="${tp:-0}"; tr="${tr:-0}"

  # ── Header ──────────────────────────────────────────────────────────────
  printf '\n%s%s' "$C_BOLD" "$C_CYAN"
  printf '%.0s═' $(seq 1 "$tw")
  printf '%s\n' "$C_RESET"
  printf '  %s%s⚡ AGENTBOARD TOKEN DASHBOARD%s   %s%s%s\n' \
    "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$period_label" "$C_RESET"
  printf '  %s%s tokens%s  ·  %s%s segs%s  ·  %s%s providers%s  ·  %s%s repos%s\n' \
    "$C_BOLD" "$(_db_ktok "$tt")" "$C_RESET" \
    "$C_BOLD" "$ts" "$C_RESET" \
    "$C_BOLD" "$tp" "$C_RESET" \
    "$C_BOLD" "$tr" "$C_RESET"
  printf '%s%s' "$C_BOLD" "$C_CYAN"
  printf '%.0s═' $(seq 1 "$tw")
  printf '%s\n' "$C_RESET"

  # ── By Provider & Model ─────────────────────────────────────────────────
  _db_section "BY PROVIDER & MODEL"
  local _found=0
  while IFS='|' read -r prov model tok; do
    [[ -z "$prov" ]] && continue; (( tok > 0 )) || continue
    _found=1
    printf '\n'
    _db_row "${prov} · ${model}" "$tok" "$tt" "$(_db_heat "$tok" "$tt")"
  done < <(sqlite3 "$db" \
    "SELECT agent_provider, COALESCE(model,'?'), SUM(total_tokens) AS t
     FROM usage WHERE $where AND total_tokens > 0
     GROUP BY agent_provider, model ORDER BY t DESC;")
  (( _found == 0 )) && printf '  %s(no data for this period)%s\n' "$C_DIM" "$C_RESET"

  # ── By Repository ───────────────────────────────────────────────────────
  _db_section "BY REPOSITORY"
  while IFS='|' read -r repo tok; do
    [[ -z "$repo" ]] && continue; (( tok > 0 )) || continue
    printf '\n'
    _db_row "$repo" "$tok" "$tt" "$(_db_heat "$tok" "$tt")"
  done < <(sqlite3 "$db" \
    "SELECT COALESCE(repo,'unknown'), SUM(total_tokens) AS t
     FROM usage WHERE $where AND total_tokens > 0
     GROUP BY repo ORDER BY t DESC;")

  # ── By Task Type with model breakdown (who did the work) ────────────────
  _db_section "BY TASK TYPE  ·  WHO DID THE WORK"
  local _prev_ttype="" _task_tot=0
  local sub_bw=$(( bar_w - 4 )); (( sub_bw < 10 )) && sub_bw=10

  while IFS='|' read -r ttype prov model row_tok type_total; do
    [[ -z "$ttype" ]] && continue
    row_tok="${row_tok:-0}"; type_total="${type_total:-1}"
    (( row_tok > 0 )) || continue

    if [[ "$ttype" != "$_prev_ttype" ]]; then
      _prev_ttype="$ttype"
      _task_tot=$type_total
      printf '\n'
      _db_row "$ttype" "$type_total" "$tt" "$(_db_heat "$type_total" "$tt")"
    fi

    local _tdenom=$_task_tot; (( _tdenom <= 0 )) && _tdenom=1
    local sub_pct=$(( row_tok * 100 / _tdenom ))
    printf '    %-20.20s  ' "${prov}·${model}"
    _db_cbar "$row_tok" "$_task_tot" "$sub_bw" "$(_db_pclr "$prov")"
    printf '  %s%s%s  %s%3d%%%s\n' \
      "$C_DIM" "$(_db_ktok "$row_tok")" "$C_RESET" "$C_DIM" "$sub_pct" "$C_RESET"
  done < <(sqlite3 "$db" "
    WITH totals AS (
      SELECT COALESCE(task_type,'chore') AS tt, SUM(total_tokens) AS type_total
      FROM usage WHERE $where AND total_tokens > 0
      GROUP BY task_type
    )
    SELECT COALESCE(u.task_type,'chore'), u.agent_provider, COALESCE(u.model,'?'),
           SUM(u.total_tokens), t.type_total
    FROM usage u
    JOIN totals t ON COALESCE(u.task_type,'chore') = t.tt
    WHERE $where AND u.total_tokens > 0
    GROUP BY u.task_type, u.agent_provider, u.model
    ORDER BY t.type_total DESC, SUM(u.total_tokens) DESC;
  ")

  # ── Daily Activity ──────────────────────────────────────────────────────
  _db_section "DAILY ACTIVITY"
  local chart_days=$period_days; (( chart_days > 14 )) && chart_days=14
  local day_bw=$(( bar_w + 8 )); (( day_bw > 36 )) && day_bw=36

  local max_day=0
  max_day="$(sqlite3 "$db" \
    "SELECT COALESCE(MAX(s),0) FROM
       (SELECT SUM(total_tokens) AS s FROM usage
        WHERE $where AND total_tokens > 0 GROUP BY date(timestamp));")"
  max_day="${max_day:-0}"

  local peak_date=''
  peak_date="$(sqlite3 "$db" \
    "SELECT date(timestamp) FROM usage WHERE $where AND total_tokens > 0
     GROUP BY date(timestamp) ORDER BY SUM(total_tokens) DESC LIMIT 1;")"

  while IFS='|' read -r d day_tok; do
    local dlbl="${d:5}"
    day_tok="${day_tok:-0}"
    if (( day_tok == 0 )); then
      printf '  %s%s%s  ' "$C_DIM" "$dlbl" "$C_RESET"
      printf '%s' "$C_DIM"; printf '%.0s·' $(seq 1 "$day_bw"); printf '%s\n' "$C_RESET"
    else
      printf '  %s%s%s  ' "$C_BOLD" "$dlbl" "$C_RESET"
      _db_cbar "$day_tok" "$max_day" "$day_bw" "$(_db_heat "$day_tok" "$max_day")"
      local pk=''
      [[ "$d" == "$peak_date" ]] && pk="$(printf '  \033[38;5;220m▲\033[0m')"
      printf '  %s%s%s%s\n' "$C_BOLD" "$(_db_ktok "$day_tok")" "$C_RESET" "$pk"
    fi
  done < <(sqlite3 "$db" "
    WITH RECURSIVE dates(d) AS (
      SELECT date('now', '-$((chart_days - 1)) days')
      UNION ALL
      SELECT date(d, '+1 day') FROM dates WHERE d < date('now')
    )
    SELECT d, COALESCE((
      SELECT SUM(total_tokens) FROM usage
      WHERE date(timestamp) = d AND total_tokens > 0
    ), 0) FROM dates ORDER BY d;
  ")

  # ── Skill Usage Frequency ───────────────────────────────────────────────
  local _sk_found=0 _sk_rank=0
  while IFS='|' read -r skill_lbl uses sk_tok; do
    [[ -z "$skill_lbl" ]] && continue
    uses="${uses:-0}"; sk_tok="${sk_tok:-0}"
    (( _sk_found == 0 )) && { _db_section "SKILL USAGE FREQUENCY"; _sk_found=1; }
    _sk_rank=$(( _sk_rank + 1 ))
    local sname="${skill_lbl#skill:}"
    printf '  %s#%d%s %-28.28s  %s%s uses%s  ·  %s%s tokens%s\n' \
      "$C_BOLD" "$_sk_rank" "$C_RESET" "$sname" \
      "$C_BOLD" "$uses" "$C_RESET" \
      "$C_DIM" "$(_db_ktok "$sk_tok")" "$C_RESET"
  done < <(sqlite3 "$db" \
    "SELECT note, COUNT(*) AS uses, SUM(total_tokens) AS tokens
     FROM usage WHERE $where AND note LIKE 'skill:%'
     GROUP BY note ORDER BY uses DESC LIMIT 8;")

  # ── Per-Stream Cost ──────────────────────────────────────────────────────
  local _ps_found=0
  while IFS='|' read -r slug tasks ps_tok; do
    [[ -z "$slug" ]] && continue
    tasks="${tasks:-0}"; ps_tok="${ps_tok:-0}"
    (( _ps_found == 0 )) && { _db_section "PER-STREAM COST"; _ps_found=1; }
    printf '  %-38.38s  %s%s tasks%s  ·  %s%s tokens%s\n' \
      "$slug" \
      "$C_BOLD" "$tasks" "$C_RESET" \
      "$C_DIM" "$(_db_ktok "$ps_tok")" "$C_RESET"
  done < <(sqlite3 "$db" \
    "SELECT stream_slug, COUNT(*) AS tasks, SUM(total_tokens) AS tokens
     FROM usage WHERE $where AND stream_slug IS NOT NULL AND stream_slug != ''
     GROUP BY stream_slug ORDER BY tokens DESC LIMIT 6;")

  # ── Model Breakdown ──────────────────────────────────────────────────────
  local _mb_rows=()
  while IFS='|' read -r mdl calls inp out; do
    [[ -z "$mdl" ]] && continue
    _mb_rows+=("${mdl}|${calls:-0}|${inp:-0}|${out:-0}")
  done < <(sqlite3 "$db" \
    "SELECT COALESCE(model,'?'), COUNT(*) AS calls,
            SUM(input_tokens), SUM(output_tokens)
     FROM usage WHERE $where
     GROUP BY model ORDER BY calls DESC;")
  if (( ${#_mb_rows[@]} > 1 )); then
    _db_section "MODEL BREAKDOWN"
    for _mb_row in "${_mb_rows[@]}"; do
      IFS='|' read -r mdl calls inp out <<< "$_mb_row"
      printf '  %-32.32s  %s%s calls%s  ·  %s%s in%s / %s%s out%s\n' \
        "$mdl" \
        "$C_BOLD" "$calls" "$C_RESET" \
        "$C_DIM" "$(_db_ktok "$inp")" "$C_RESET" \
        "$C_DIM" "$(_db_ktok "$out")" "$C_RESET"
    done
  fi

  printf '\n'
}
