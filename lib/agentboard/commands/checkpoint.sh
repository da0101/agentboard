_checkpoint_print_migration_blocker() {
  local stream_file="$1" slug="$2" what="$3" next_action="$4" blocker="$5" focus="$6"
  local explicit_blocker="$7" explicit_focus="$8" include_diff="$9"
  shift 9
  local tokens_in="$1" tokens_out="$2" cum_in="$3" cum_out="$4" provider="$5" model="$6" task_type="$7" complexity="$8"

  local -a retry_cmd=()
  retry_cmd=(ab checkpoint "$slug" --what "$what" --next "$next_action")
  [[ "$explicit_blocker" -eq 1 ]] && retry_cmd+=(--blocker "$blocker")
  [[ "$explicit_focus" -eq 1 ]] && retry_cmd+=(--focus "$focus")
  [[ "$include_diff" -eq 1 ]] && retry_cmd+=(--diff)
  [[ -n "$tokens_in" ]] && retry_cmd+=(--tokens-in "$tokens_in")
  [[ -n "$tokens_out" ]] && retry_cmd+=(--tokens-out "$tokens_out")
  [[ -n "$cum_in" ]] && retry_cmd+=(--cumulative-in "$cum_in")
  [[ -n "$cum_out" ]] && retry_cmd+=(--cumulative-out "$cum_out")
  [[ -n "$provider" ]] && retry_cmd+=(--provider "$provider")
  [[ -n "$model" ]] && retry_cmd+=(--model "$model")
  [[ -n "$task_type" ]] && retry_cmd+=(--type "$task_type")
  [[ -n "$complexity" ]] && retry_cmd+=(--complexity "$complexity")

  printf '  %s✖%s  %s has no v1 frontmatter.\n' "$C_RED" "$C_RESET" "$stream_file" >&2
  printf '     Run migration, then retry the same checkpoint payload:\n' >&2
  printf '       %sab migrate --apply%s\n' "$C_BOLD" "$C_RESET" >&2
  printf '       %s' "$C_BOLD" >&2
  printf '%q ' "${retry_cmd[@]}" >&2
  printf '%s\n' "$C_RESET" >&2
}

cmd_checkpoint() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  if [[ "${1:-}" == "--auto" ]]; then
    _checkpoint_auto_mode "${2:-}"
    return 0
  fi

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      slug=""
    else
      die "Usage: ab checkpoint <stream-slug> --what \"...\" --next \"...\" [--blocker \"...\"] [--focus \"...\"] [--diff] [--dry-run]"
    fi
  else
    shift
  fi
  if [[ -n "$slug" ]]; then
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."
  fi

  local what="" next_action="" blocker="" focus="" include_diff=0 dry_run=0
  local explicit_blocker=0 explicit_focus=0
  local tokens_in="" tokens_out="" provider="" model="" complexity="" task_type=""
  local cum_in="" cum_out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --what)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --what"
        what="$2"; shift 2 ;;
      --next)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --next"
        next_action="$2"; shift 2 ;;
      --blocker)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --blocker"
        blocker="$2"; explicit_blocker=1; shift 2 ;;
      --focus)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --focus"
        focus="$2"; explicit_focus=1; shift 2 ;;
      --diff) include_diff=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --tokens-in)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --tokens-in"
        tokens_in="$2"; shift 2 ;;
      --tokens-out)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --tokens-out"
        tokens_out="$2"; shift 2 ;;
      --cumulative-in)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --cumulative-in"
        cum_in="$2"; shift 2 ;;
      --cumulative-out)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --cumulative-out"
        cum_out="$2"; shift 2 ;;
      --provider)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --provider"
        provider="$2"; shift 2 ;;
      --model)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --model"
        model="$2"; shift 2 ;;
      --complexity)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --complexity"
        complexity="$2"; shift 2 ;;
      --type)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --type"
        task_type="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: ab checkpoint <stream-slug> --what "..." --next "..." [flags]

Updates `## Resume state`, prepends `## Progress log`, and trims to 10 entries.

Required: --what "<1-2 lines>" --next "<one sentence>"
Optional: --blocker "<text>" --focus "<file:line|topic>" --diff --dry-run
Usage: --provider <name> --model <name> [--type <name>] [--complexity <t>]
       --tokens-in N --tokens-out N
       --cumulative-in N --cumulative-out N

Use token deltas OR cumulative totals, not both. Resume with: ab handoff <stream-slug>
EOF
        return 0 ;;
      *) die "Unknown flag for checkpoint: $1" ;;
    esac
  done

  # Env-var fallbacks for provider/model so agents can set them once per shell
  [[ -z "$provider" ]] && provider="${AGENTBOARD_PROVIDER:-}"
  [[ -z "$model" ]] && model="${AGENTBOARD_MODEL:-}"

  [[ -n "$what" ]] || die "checkpoint requires --what \"<1-2 lines>\""
  [[ -n "$next_action" ]] || die "checkpoint requires --next \"<one sentence>\""

  (( explicit_blocker )) || blocker="none"
  (( explicit_focus )) || focus="—"

  what="${what//$'\n'/ }"
  next_action="${next_action//$'\n'/ }"
  blocker="${blocker//$'\n'/ }"
  focus="${focus//$'\n'/ }"

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (ab new-stream)."
  if ! has_frontmatter "$stream_file"; then
    _checkpoint_print_migration_blocker "$stream_file" "$slug" "$what" "$next_action" "$blocker" "$focus" \
      "$explicit_blocker" "$explicit_focus" "$include_diff" \
      "$tokens_in" "$tokens_out" "$cum_in" "$cum_out" "$provider" "$model" "$task_type" "$complexity"
    return 1
  fi

  local today_str ts agent
  today_str="$(today)"
  ts="$(date '+%Y-%m-%d %H:%M')"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  local resume_block
  resume_block="$(cat <<EOF
## Resume state
_Overwritten by \`ab checkpoint\` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** ${today_str} by ${agent}
- **What just happened:** ${what}
- **Current focus:** ${focus}
- **Next action:** ${next_action}
- **Blockers:** ${blocker}
EOF
  )"

  local log_entry
  log_entry="${ts} — ${what}"
  if (( include_diff )); then
    if git rev-parse --git-dir >/dev/null 2>&1; then
      local base_branch base_ref head_branch stat_raw
      base_branch="$(frontmatter_value "$stream_file" "base_branch")"
      if ! is_placeholder_value "$base_branch" && [[ -n "$base_branch" ]]; then
        if git rev-parse --verify --quiet "$base_branch" >/dev/null; then
          base_ref="$base_branch"
        elif git rev-parse --verify --quiet "origin/$base_branch" >/dev/null; then
          base_ref="origin/$base_branch"
        fi
        if [[ -n "$base_ref" ]]; then
          head_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'HEAD')"
          stat_raw="$(git diff --stat "$base_ref"...HEAD 2>/dev/null || true)"
          if [[ -n "$(printf '%s' "$stat_raw" | tr -d ' \t\n')" ]]; then
            log_entry="${log_entry}"$'\n'"    diff ${head_branch} vs ${base_ref}:"$'\n'"$(printf '%s\n' "$stat_raw" | sed 's/^/      /')"
          fi
        fi
      fi
    fi
  fi

  if (( dry_run )); then
    printf '%sWould update %s%s\n\n' "$C_BOLD" "$stream_file" "$C_RESET"
    printf '%sResume state:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n\n' "$resume_block"
    printf '%sProgress log entry (prepended, kept latest 10):%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' "$log_entry"
    return 0
  fi

  platform_with_lock "stream-${slug}" _checkpoint_apply_writes \
    "$stream_file" "$resume_block" "$log_entry" "$today_str"

  ok "Checkpoint saved to $stream_file"
  say "  ${C_DIM}next:${C_RESET} ${next_action}"
  say "  ${C_DIM}Ready for handoff — run: ab handoff ${slug}${C_RESET}"

  _checkpoint_auto_log_usage "$slug" "$tokens_in" "$tokens_out" "$cum_in" "$cum_out" "$provider" "$model" "$complexity" "$task_type" "$what"
}

_checkpoint_infer_task_type() {
  local what="$1"
  local lower
  lower="$(printf '%s' "$what" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *audit*|*review*|*analysis*)
      printf 'audit' ;;
    *debug*|*bug*|*fix*|*error*|*regression*|*investigat*)
      printf 'debug' ;;
    *design*|*architect*|*scope*|*plan*|*proposal*)
      printf 'design' ;;
    *research*|*doc*|*read*|*explor*)
      printf 'research' ;;
    *implement*|*implementation*|*code*|*test*|*refactor*|*build*|*write*)
      printf 'implementation' ;;
    *handoff*|*resume*|*checkpoint*)
      printf 'handoff' ;;
    *question*|*clarif*|*brainstorm*|*discuss*|*conversation*)
      printf 'conversation' ;;
    *)
      printf 'chore' ;;
  esac
}

_checkpoint_auto_mode() {
  local requested_slug="${1:-}"
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  [[ -d "./.platform" ]] || return 0

  local slug="$requested_slug"
  if [[ -z "$slug" ]]; then
    local active=() f st
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      st="$(frontmatter_value "$f" "status" 2>/dev/null)" || continue
      case "$st" in done|archived|closed) continue ;; esac
      active+=("$(basename "$f" .md)")
    done < <(stream_files 2>/dev/null)
    (( ${#active[@]} == 1 )) || return 0
    slug="${active[0]}"
  fi

  [[ -n "$slug" ]] || return 0
  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || return 0
  has_frontmatter "$stream_file" 2>/dev/null || return 0

  local head_hash commit_msg
  head_hash="$(git rev-parse --short HEAD 2>/dev/null)" || return 0
  commit_msg="$(git log -1 --format='%s' 2>/dev/null)" || return 0
  [[ -n "$commit_msg" ]] || return 0

  # Idempotency: if this commit hash was already auto-recorded, skip.
  grep -qF "(auto) ${head_hash}" "$stream_file" 2>/dev/null && return 0

  local today_str agent ts what
  today_str="$(today)"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"
  ts="$(date '+%Y-%m-%d %H:%M')"
  what="(auto) ${head_hash}: ${commit_msg}"

  local resume_block
  resume_block="$(cat <<EOF
## Resume state
_Overwritten by \`ab checkpoint\` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** ${today_str} by ${agent} (auto)
- **What just happened:** ${what}
- **Current focus:** —
- **Next action:** (auto-saved from commit — update next action manually)
- **Blockers:** none
EOF
)"

  platform_with_lock "stream-${slug}" _checkpoint_apply_writes \
    "$stream_file" "$resume_block" "${ts} — ${what}" "$today_str" 2>/dev/null || return 0
  return 0
}

_checkpoint_apply_writes() {
  local stream_file="$1" resume_block="$2" log_entry="$3" today_str="$4"
  _checkpoint_write_resume_state "$stream_file" "$resume_block"
  _checkpoint_prepend_progress_entry "$stream_file" "$log_entry"
  replace_frontmatter_line "$stream_file" "updated_at" "$today_str"
}

_checkpoint_auto_log_usage() {
  local slug="$1" tokens_in="$2" tokens_out="$3" cum_in="$4" cum_out="$5"
  local provider="$6" model="$7" complexity="$8" task_type="$9" what="${10}"
  [[ -n "$provider" ]] || return 0

  if [[ -z "$task_type" ]]; then
    task_type="$(_checkpoint_infer_task_type "$what")"
  fi

  local mode=""
  if [[ -n "$cum_in" || -n "$cum_out" ]]; then
    [[ -n "$cum_in" && -n "$cum_out" ]] || {
      warn "Checkpoint: --cumulative-in and --cumulative-out must be passed together; skipping usage log"
      return 0
    }
    [[ "$cum_in" =~ ^[0-9]+$ && "$cum_out" =~ ^[0-9]+$ ]] || {
      warn "Checkpoint: --cumulative-in/--cumulative-out must be non-negative integers; skipping usage log"
      return 0
    }
    if [[ -n "$tokens_in" || -n "$tokens_out" ]]; then
      warn "Checkpoint: use --tokens-in/out OR --cumulative-in/out, not both; skipping usage log"
      return 0
    fi
    mode="cumulative"
  elif [[ -n "$tokens_in" && -n "$tokens_out" ]]; then
    [[ "$tokens_in" =~ ^[0-9]+$ && "$tokens_out" =~ ^[0-9]+$ ]] || {
      warn "Checkpoint: --tokens-in/--tokens-out must be integers; skipping usage log"
      return 0
    }
    mode="delta"
  else
    return 0
  fi

  command -v cmd_usage >/dev/null 2>&1 || return 0

  local -a usage_args=(
    log
    --provider "$provider"
    --stream "$slug"
    --type "$task_type"
  )
  if [[ "$mode" == "cumulative" ]]; then
    usage_args+=(--cumulative-in "$cum_in" --cumulative-out "$cum_out")
  else
    usage_args+=(--input "$tokens_in" --output "$tokens_out")
  fi
  [[ -n "$model" ]] && usage_args+=(--model "$model")
  [[ -n "$complexity" ]] && usage_args+=(--complexity "$complexity")
  local note="checkpoint: ${what:0:80}"
  usage_args+=(--note "$note")

  if cmd_usage "${usage_args[@]}" >/dev/null 2>&1; then
    if [[ "$mode" == "cumulative" ]]; then
      say "  ${C_DIM}usage logged: ${provider}${model:+/$model} — cumulative ${cum_in} in / ${cum_out} out (delta auto-computed)${C_RESET}"
    else
      say "  ${C_DIM}usage logged: ${provider}${model:+/$model} — ${tokens_in} in / ${tokens_out} out${C_RESET}"
    fi
  fi
}

_checkpoint_write_resume_state() {
  local file="$1" new_block="$2"
  local tmp block_file
  tmp="$(mktemp)"
  block_file="$(mktemp)"
  printf '%s\n' "$new_block" > "$block_file"

  if grep -q '^## Resume state[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { in_section = 0; printed = 0 }
      /^## Resume state[[:space:]]*$/ {
        if (!printed) {
          while ((getline line < block_file) > 0) print line
          close(block_file)
          printed = 1
        }
        in_section = 1
        next
      }
      in_section && /^## / { in_section = 0; print ""; print; next }
      in_section { next }
      { print }
    ' "$file" > "$tmp"
  elif grep -q '^## Progress log[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { inserted = 0 }
      /^## Progress log[[:space:]]*$/ && !inserted {
        while ((getline line < block_file) > 0) print line
        close(block_file)
        print ""
        inserted = 1
      }
      { print }
    ' "$file" > "$tmp"
  elif grep -q '^## Next action[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { inserted = 0 }
      /^## Next action[[:space:]]*$/ && !inserted {
        while ((getline line < block_file) > 0) print line
        close(block_file)
        print ""
        inserted = 1
      }
      { print }
    ' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '\n' >> "$tmp"
    cat "$block_file" >> "$tmp"
    printf '\n' >> "$tmp"
  fi

  rm -f "$block_file"
  mv "$tmp" "$file"
}

_checkpoint_prepend_progress_entry() {
  local file="$1" entry="$2"
  local tmp entry_file
  tmp="$(mktemp)"
  entry_file="$(mktemp)"
  printf '%s\n' "$entry" > "$entry_file"

  if ! grep -q '^## Progress log[[:space:]]*$' "$file"; then
    {
      cat "$file"
      printf '\n## Progress log\n_Append-only. Auto-trimmed by `ab checkpoint` to last 10 entries._\n\n'
      cat "$entry_file"
      printf '\n'
    } > "$tmp"
    rm -f "$entry_file"
    mv "$tmp" "$file"
    return 0
  fi

  awk -v entry_file="$entry_file" '
    BEGIN { in_log = 0; inserted = 0; count = 0 }
    /^## Progress log[[:space:]]*$/ {
      print
      in_log = 1
      next
    }
    in_log && !inserted && (/^_.*_[[:space:]]*$/ || /^[[:space:]]*$/) {
      print
      next
    }
    in_log && !inserted {
      while ((getline line < entry_file) > 0) print line
      close(entry_file)
      print ""
      inserted = 1
      count = 1
      # fall through to process current line
    }
    in_log && /^## / {
      in_log = 0
    }
    in_log {
      if ($0 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
        count++
        if (count > 10) { skipping = 1 }
        else            { skipping = 0 }
      }
      if (skipping) next
    }
    { print }
    END {
      if (in_log && !inserted) {
        while ((getline line < entry_file) > 0) print line
        close(entry_file)
      }
    }
  ' "$file" > "$tmp"

  rm -f "$entry_file"
  mv "$tmp" "$file"
}
