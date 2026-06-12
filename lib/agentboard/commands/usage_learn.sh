# Usage monitoring — `ab usage learn` pattern analysis

# Emit a learning entry as a markdown bullet for .platform/memory/learnings.md
_learning_entry() {
  local date today
  today="$(date +%Y-%m-%d)"
  printf '%s\n' "- [$today] [token-optimization] $1"
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

  # ── Conversational Opus waste: expensive conversation on premium model ────
  while IFS='|' read -r model avg_tokens segments; do
    [[ -z "$model" ]] && continue
    printf 'CONVERSATION_OVERSPEND|%s|%.0f|%s\n' "$model" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT model, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE lower(task_type) = 'conversation' AND model LIKE '%opus%' AND total_tokens > 0
    GROUP BY model
    HAVING n >= 2 AND avg > 30000
    ORDER BY avg DESC;
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

  # ── Generic task labels hide root cause analysis ──────────────────────────
  while IFS='|' read -r count total; do
    [[ -z "$count" || "$count" == "0" ]] && continue
    printf 'GENERIC_TASK_LABELS|%s|%s|-\n' "$count" "$total"
  done < <(sqlite3 "$db" "
    SELECT COUNT(*), COALESCE(SUM(total_tokens),0)
    FROM usage
    WHERE lower(COALESCE(task_type,'')) IN
      ('normal','heavy','trivial','small','medium','large','xl');
  ")

  # ── Coarse logging: huge spend spread across too few checkpoints ──────────
  while IFS='|' read -r stream segments total max_seg; do
    [[ -z "$stream" ]] && continue
    printf 'COARSE_LOGGING|%s|%s|%s|%s\n' "$stream" "$segments" "$total" "$max_seg"
  done < <(sqlite3 "$db" "
    SELECT stream_slug, COUNT(*) AS n, SUM(total_tokens) AS total, MAX(total_tokens) AS max_seg
    FROM usage
    WHERE stream_slug IS NOT NULL AND stream_slug != '' AND total_tokens > 0
    GROUP BY stream_slug
    HAVING total >= 200000 AND n <= 2
    ORDER BY total DESC
    LIMIT 5;
  ")
}

# Called only from cmd_usage, which provides $db in scope.
_usage_learn_cmd() {
  local apply=0 learnings_file="./.platform/memory/learnings.md"
  [[ "${1:-}" == "--apply" ]] && apply=1

  printf '\n%s%sUsage Learning Analysis%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

  local total_rows
  total_rows="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE total_tokens > 0;")"
  if [[ "$total_rows" -lt 5 ]]; then
    warn "Not enough data yet ($total_rows segments logged). Need at least 5 to generate learnings."
    say
    printf '%sKeep logging with: ab usage log --provider ... --input ... --output ...%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local findings=() recommendations=() new_learnings=()
  local kind a b c d

  while IFS='|' read -r kind a b c d; do
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
      CONVERSATION_OVERSPEND)
        local model="$a" avg="$b" segs="$c"
        local rec="Conversation segments are averaging ${avg} tokens on ${model}. Move routine discussion to Sonnet and checkpoint earlier when the work changes from conversation to execution."
        local learning="Conversation work on ${model} is expensive (avg ${avg} tokens, ${segs} samples). Default conversation and planning to Sonnet unless there is clear high-risk reasoning value."
        printf '  %s⚠ CONVERSATION_OVERSPEND%s  %s — avg %s tokens (%s segs)\n' \
          "$C_YELLOW" "$C_RESET" "$model" "$avg" "$segs"
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
      GENERIC_TASK_LABELS)
        local count="$a" total="$b"
        local rec="${count} historical usage rows still use generic labels like normal/heavy. Future checkpoints should pass --type so token waste is explainable by work kind, not just size."
        local learning="Generic task labels (normal/heavy/etc.) hide spend root causes. Always log usage with semantic task types such as conversation, design, implementation, debug, audit, or handoff."
        printf '  %s⚠ GENERIC_TASK_LABELS%s  %s generic rows covering %s tokens\n' \
          "$C_YELLOW" "$C_RESET" "$count" "$total"
        printf '    → %s\n\n' "$rec"
        new_learnings+=("$learning")
        ;;
      COARSE_LOGGING)
        local stream="$a" segs="$b" total="$c" max_seg="$d"
        local rec="Stream '${stream}' logged ${total} tokens across only ${segs} segment(s), with a largest segment of ${max_seg}. Checkpoint at stage boundaries so waste can be attributed before the context is nearly full."
        local learning="High-token streams with too few checkpoints become opaque. For large streams, checkpoint at every stage change (research, design, implementation, audit) instead of only at the end."
        printf '  %s⚠ COARSE_LOGGING%s  %s — %s tokens across %s segment(s), max segment %s\n' \
          "$C_YELLOW" "$C_RESET" "$stream" "$total" "$segs" "$max_seg"
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
      warn "No .platform/memory/learnings.md found in current directory. Run from inside a project."
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
    printf '%sRun with --apply to write these findings to .platform/memory/learnings.md%s\n' \
      "$C_DIM" "$C_RESET"
    printf '%sThe LLM reads learnings.md at session start and adjusts its behaviour.%s\n' \
      "$C_DIM" "$C_RESET"
  fi
}
