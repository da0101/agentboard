# -----------------------------------------------------------------------------
# ab usage ingest — read REAL token counts from Claude Code and Codex session
# transcripts into the usage database. Replaces agent self-reporting.
#
#   ab usage ingest [--all] [--since YYYY-MM-DD] [--dry-run] [--quiet]
#   ab usage migrate                 merge the legacy ~/.agentboard/usage.db
#
# Grain: one row per (provider, session, model, UTC day) — re-running updates
# the same rows (idempotent) and never touches manual annotations such as
# stream_slug / task_type. Parsers are awk over JSONL: no jq/python needed.
#   Claude: ~/.claude/projects/<encoded cwd>/<session>.jsonl, assistant records,
#           deduped by message id (a message is streamed as several records).
#   Codex:  ~/.codex/sessions/**/rollout-*.jsonl, deltas of the cumulative
#           token_count totals, attributed to the model of the current turn.
# Override locations with AGENTBOARD_CLAUDE_DIR / AGENTBOARD_CODEX_DIR (tests).
# -----------------------------------------------------------------------------

USAGE_NUM_AWK='function num(s, key,   m) {
  if (match(s, "\"" key "\":[0-9]+")) { m = substr(s, RSTART, RLENGTH); sub(/^.*:/, "", m); return m + 0 }
  return 0 }'

# _usage_parse_claude <file...> — TSV: day model fresh_in cache_read cache_write out reasoning
# (a session = main transcript + its subagents/*.jsonl; message ids dedupe across them)
_usage_parse_claude() {
  awk "$USAGE_NUM_AWK"'
    /"type":"assistant"/ && /"usage":\{/ {
      if (!match($0, /"id":"msg_[A-Za-z0-9_]+"/)) next
      id = substr($0, RSTART + 6, RLENGTH - 7)
      day = ""; if (match($0, /"timestamp":"[^"]+"/)) day = substr($0, RSTART + 13, 10)
      model = ""; if (match($0, /"model":"[^"]+"/)) model = substr($0, RSTART + 9, RLENGTH - 10)
      if (!match($0, /"usage":\{[^}]*/)) next
      u = substr($0, RSTART, RLENGTH)
      D[id] = day; M[id] = model
      I[id] = num(u, "input_tokens"); R[id] = num(u, "cache_read_input_tokens")
      W[id] = num(u, "cache_creation_input_tokens"); O[id] = num(u, "output_tokens")
      T[id] = num(u, "thinking_tokens")
    }
    END {
      for (id in D) {
        if (D[id] == "" || M[id] == "" || M[id] ~ /^</) continue
        if (I[id] + R[id] + W[id] + O[id] == 0) continue
        k = D[id] "\t" M[id]
        ai[k] += I[id]; ar[k] += R[id]; aw[k] += W[id]; ao[k] += O[id]; at[k] += T[id]
      }
      for (k in ai) printf "%s\t%d\t%d\t%d\t%d\t%d\n", k, ai[k], ar[k], aw[k], ao[k], at[k]
    }' "$@"
}

# _usage_parse_codex <file> — same TSV. Totals are cumulative: sum the deltas.
_usage_parse_codex() {
  awk "$USAGE_NUM_AWK"'
    /"type":"turn_context"/ { if (match($0, /"model":"[^"]+"/)) model = substr($0, RSTART + 9, RLENGTH - 10) }
    /"type":"token_count"/ && /"total_token_usage":\{/ {
      day = ""; if (match($0, /"timestamp":"[^"]+"/)) day = substr($0, RSTART + 13, 10)
      if (!match($0, /"total_token_usage":\{[^}]*\}/)) next
      u = substr($0, RSTART, RLENGTH)
      in_ = num(u, "input_tokens"); ca = num(u, "cached_input_tokens"); cw = num(u, "cache_write_input_tokens")
      out = num(u, "output_tokens"); rs = num(u, "reasoning_output_tokens")
      if (in_ < pin || out < pout) { pin = 0; pca = 0; pcw = 0; pout = 0; prs = 0 }   # counter reset
      di = (in_ - pin) - (ca - pca); if (di < 0) di = 0
      if (day == "" || model == "") { pin = in_; pca = ca; pcw = cw; pout = out; prs = rs; next }
      k = day "\t" model
      ai[k] += di; ar[k] += (ca - pca); aw[k] += (cw - pcw); ao[k] += (out - pout); at[k] += (rs - prs)
      pin = in_; pca = ca; pcw = cw; pout = out; prs = rs
    }
    END { for (k in ai) if (ai[k] + ar[k] + aw[k] + ao[k] > 0) printf "%s\t%d\t%d\t%d\t%d\t%d\n", k, ai[k], ar[k], aw[k], ao[k], at[k] }' "$1"
}

_usage_sql_quote() { printf '%s' "${1//\'/\'\'}"; }

# _usage_encode_path <path> — Claude Code's project-dir name (non-alnum -> '-')
_usage_encode_path() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# _usage_session_cwd <file> — first "cwd" recorded in a transcript
_usage_session_cwd() { grep -m1 -o '"cwd":"[^"]*"' "$1" 2>/dev/null | sed 's/^"cwd":"//; s/"$//'; }

# _usage_emit_rows <provider> <session> <repo> <since> <file...> — SQL upserts on stdout
_usage_emit_rows() {
  local provider="$1" session="$2" repo="$3" since="$4"; shift 4
  { if [[ "$provider" == claude ]]; then _usage_parse_claude "$@"; else _usage_parse_codex "$1"; fi; } \
  | while IFS=$'\t' read -r day model fin cr cw out rs; do
    [[ -z "$since" || "$day" > "$since" || "$day" == "$since" ]] || continue
    printf "INSERT INTO usage (timestamp, agent_provider, model, repo, session_id, day, input_tokens, cache_read_tokens, cache_write_tokens, output_tokens, reasoning_tokens, total_tokens, source) VALUES ('%s 12:00:00','%s','%s','%s','%s','%s',%d,%d,%d,%d,%d,%d,'ingest') ON CONFLICT(agent_provider, session_id, model, day) DO UPDATE SET input_tokens=excluded.input_tokens, cache_read_tokens=excluded.cache_read_tokens, cache_write_tokens=excluded.cache_write_tokens, output_tokens=excluded.output_tokens, reasoning_tokens=excluded.reasoning_tokens, total_tokens=excluded.total_tokens, repo=COALESCE(usage.repo, excluded.repo);\n" \
      "$day" "$provider" "$(_usage_sql_quote "$model")" "$(_usage_sql_quote "$repo")" "$(_usage_sql_quote "$session")" "$day" \
      "$fin" "$cr" "$cw" "$out" "$rs" "$((fin + cr + cw + out))"
  done
}

_usage_ingest_cmd() {
  local all=0 since="" dry=0 quiet=0 root files=0 rows=0 sql f sess cwd repo dir cdir xdir
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1; shift ;;
      --since) since="${2:-}"; [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--since needs YYYY-MM-DD"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --quiet|-q) quiet=1; shift ;;
      *) die "Unknown flag for usage ingest: $1" ;;
    esac
  done
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cdir="${AGENTBOARD_CLAUDE_DIR:-$HOME/.claude/projects}"
  xdir="${AGENTBOARD_CODEX_DIR:-$HOME/.codex/sessions}"
  _usage_migrate_legacy quiet
  sql="$(mktemp)"; printf 'BEGIN;\n' > "$sql"

  if [[ -d "$cdir" ]]; then
    for dir in "$cdir"/*/; do
      dir="${dir%/}"
      if (( ! all )); then
        case "$(basename "$dir")/" in "$(_usage_encode_path "$root")"/*|"$(_usage_encode_path "$root")"-*) ;; *) continue ;; esac
      fi
      for f in "$dir"/*.jsonl; do
        [[ -f "$f" ]] || continue
        [[ -z "$since" ]] || [[ -n "$(find "$f" -newermt "$since" 2>/dev/null)" ]] || continue
        sess="$(basename "$f" .jsonl)"; cwd="$(_usage_session_cwd "$f")"
        if (( all )); then repo="$(basename "${cwd:-$dir}")"; else repo="$(basename "$root")"; fi
        local -a parts=("$f"); local sub
        for sub in "$dir/$sess"/subagents/*.jsonl; do [[ -f "$sub" ]] && parts+=("$sub"); done
        _usage_emit_rows claude "$sess" "$repo" "$since" "${parts[@]}" >> "$sql"; files=$((files + ${#parts[@]}))
      done
    done
  fi
  if [[ -d "$xdir" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      cwd="$(_usage_session_cwd "$f")"
      if (( ! all )); then case "$cwd" in "$root"|"$root"-*|"$root"/*) ;; *) continue ;; esac; fi
      sess="$(basename "$f" .jsonl)"; sess="${sess##*-????-??-??T??-??-??-}"
      if (( all )); then repo="$(basename "${cwd:-unknown}")"; else repo="$(basename "$root")"; fi
      _usage_emit_rows codex "$sess" "$repo" "$since" "$f" >> "$sql"; files=$((files + 1))
    done < <(find "$xdir" -name 'rollout-*.jsonl' ${since:+-newermt "$since"} 2>/dev/null)
  fi

  printf 'COMMIT;\n' >> "$sql"
  rows="$(grep -c '^INSERT' "$sql" || true)"
  if (( dry )); then
    (( quiet )) || say "  ${files} transcript(s) → ${rows} row(s) (dry run, nothing written)"
  else
    sqlite3 "$_usage_db" < "$sql" || { rm -f "$sql"; die "Could not write usage rows."; }
    (( quiet )) || ok "Ingested ${rows} row(s) from ${files} transcript(s) into ${_usage_db}"
  fi
  rm -f "$sql"
}

# _usage_migrate_legacy [quiet] — fold ~/.agentboard/usage.db into the live db once
_usage_migrate_legacy() {
  local old="$HOME/.agentboard/usage.db" n
  [[ -z "${AGENTBOARD_USAGE_DB:-}" ]] || return 0     # explicit db path (tests): leave legacy alone
  [[ -f "$old" && "$old" != "$_usage_db" ]] || return 0
  n="$(sqlite3 "$_usage_db" "ATTACH '$(_usage_sql_quote "$old")' AS old;
    INSERT INTO usage (timestamp, agent_provider, model, stream_slug, repo, task_type, task_complexity, input_tokens, output_tokens, total_tokens, estimated_cost, note, session_id, source)
      SELECT o.timestamp, o.agent_provider, o.model, o.stream_slug, o.repo, o.task_type, o.task_complexity, o.input_tokens, o.output_tokens, o.total_tokens, o.estimated_cost, o.note, o.session_id, 'manual'
      FROM old.usage o WHERE NOT EXISTS (SELECT 1 FROM main.usage u WHERE u.timestamp = o.timestamp AND u.agent_provider = o.agent_provider
        AND u.repo IS o.repo AND u.input_tokens IS o.input_tokens AND u.output_tokens IS o.output_tokens);
    SELECT changes();" 2>/dev/null | tail -1)"
  mv "$old" "${old}.merged" 2>/dev/null || true
  [[ "${1:-}" == quiet ]] || ok "Merged legacy usage db (${n:-0} row(s)); kept as ${old}.merged"
}
