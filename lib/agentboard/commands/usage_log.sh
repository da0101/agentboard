# Usage monitoring — `ab usage log` subcommand

# Log one usage segment (direct or cumulative mode). Called only from
# cmd_usage, which provides $db in scope.
_usage_log_cmd() {
  local provider="" model="" stream="" input=0 output=0 repo="" type="chore" complexity="" note=""
  local cum_in="" cum_out="" session_key=""
  repo="$(basename "$(pwd)")"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --model)    model="$2";    shift 2 ;;
      --stream)   stream="$2";   shift 2 ;;
      --repo)     repo="$2";     shift 2 ;;
      --type)     type="$2";     shift 2 ;;
      --complexity) complexity="$2"; shift 2 ;;
      --input)    input="$2";    shift 2 ;;
      --output)   output="$2";   shift 2 ;;
      --cumulative-in)  cum_in="$2";  shift 2 ;;
      --cumulative-out) cum_out="$2"; shift 2 ;;
      --session-key)    session_key="$2"; shift 2 ;;
      --note)     note="$2";     shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$provider" ]] || die "Usage: ab usage log --provider <name> (--input <N> --output <N> | --cumulative-in <N> --cumulative-out <N>) [--model <M>] [--stream <S>] [--session-key <K>] [--repo <R>] [--type <T>] [--complexity <C>] [--note <text>]"

  # Cumulative mode: Claude/Codex/Gemini report running session totals, not
  # per-segment deltas. Compute delta = cumulative - sum-logged-so-far for
  # this session, so each log row stores the actual segment usage.
  if [[ -n "$cum_in" || -n "$cum_out" ]]; then
    [[ -n "$cum_in" && -n "$cum_out" ]] \
      || die "--cumulative-in and --cumulative-out must be used together"
    [[ "$cum_in" =~ ^[0-9]+$ && "$cum_out" =~ ^[0-9]+$ ]] \
      || die "--cumulative-in/--cumulative-out must be non-negative integers"

    # Default session scope: same stream + same provider + same calendar day.
    # Users can override with --session-key for custom grouping.
    local default_key="${stream}|${provider}|$(date +%Y-%m-%d)"
    local key="${session_key:-$default_key}"

    local prev_in prev_out
    prev_in="$(_usage_session_sum "$db" "$key" input_tokens)"
    prev_out="$(_usage_session_sum "$db" "$key" output_tokens)"
    [[ -z "$prev_in" ]] && prev_in=0
    [[ -z "$prev_out" ]] && prev_out=0

    local delta_in=$(( cum_in - prev_in ))
    local delta_out=$(( cum_out - prev_out ))

    # Negative delta = session reset (new CLI session with fresh counter).
    # Log the cumulative as-is — it represents a full fresh session.
    local reset_note=""
    if (( delta_in < 0 || delta_out < 0 )); then
      delta_in="$cum_in"
      delta_out="$cum_out"
      reset_note=" (session reset detected — logging cumulative as fresh segment)"
    fi

    input="$delta_in"
    output="$delta_out"
    printf '  %scumulative: %s in / %s out · session-so-far: %s in / %s out · delta: %s in / %s out%s%s\n' \
      "$C_DIM" "$cum_in" "$cum_out" "$prev_in" "$prev_out" \
      "$delta_in" "$delta_out" "$reset_note" "$C_RESET"
  fi

  local total=$((input + output))
  local _sql_p="${provider//\'/\'\'}"   _sql_m="${model//\'/\'\'}"
  local _sql_s="${stream//\'/\'\'}"     _sql_r="${repo//\'/\'\'}"
  local _sql_t="${type//\'/\'\'}"       _sql_c="${complexity//\'/\'\'}"
  local _sql_n="${note//\'/\'\'}"
  sqlite3 "$db" "INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, task_complexity, input_tokens, output_tokens, total_tokens, note)
    VALUES ('$_sql_p', '$_sql_m', '$_sql_s', '$_sql_r', '$_sql_t', '$_sql_c', $input, $output, $total, '$_sql_n');"
  ok "Logged $total tokens  (provider=$provider repo=$repo stream=${stream:-none} type=$type)"
  [[ -n "$note" ]] && printf '  note: %s\n' "$note" || true
}
