cmd_checkpoint() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      slug=""
    else
      die "Usage: agentboard checkpoint <stream-slug> --what \"...\" --next \"...\" [--blocker \"...\"] [--focus \"...\"] [--diff] [--dry-run]"
    fi
  else
    shift
  fi
  if [[ -n "$slug" ]]; then
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."
  fi

  local what="" next_action="" blocker="" focus="" include_diff=0 dry_run=0
  local explicit_blocker=0 explicit_focus=0
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
      -h|--help)
        cat <<'EOF'
Usage: agentboard checkpoint <stream-slug> --what "..." --next "..." [flags]

Overwrites the stream file's `## Resume state` block so the next agent has
compact, current context. Also prepends a dated entry to `## Progress log`
and trims the log to the last 10 entries.

Required:
  --what "<1-2 lines>"     What just happened in this session.
  --next "<one sentence>"  The single next action for whoever resumes.

Optional:
  --blocker "<text>"       Current blocker. Defaults to "none".
  --focus "<file:line|topic>"  What file/topic is in focus. Defaults to "—".
  --diff                   Also append `git diff --stat` to Progress log.
  --dry-run                Print what would change; don't write.

After running, the next agent (Claude/Codex/Gemini) can resume by running
`agentboard handoff <stream-slug>` and reading Resume state first.
EOF
        return 0 ;;
      *) die "Unknown flag for checkpoint: $1" ;;
    esac
  done

  [[ -n "$what" ]] || die "checkpoint requires --what \"<1-2 lines>\""
  [[ -n "$next_action" ]] || die "checkpoint requires --next \"<one sentence>\""

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (agentboard new-stream)."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  local today_str ts agent
  today_str="$(today)"
  ts="$(date '+%Y-%m-%d %H:%M')"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  (( explicit_blocker )) || blocker="none"
  (( explicit_focus )) || focus="—"

  # Sanitize single-line fields: no newlines, no pipe tricks
  what="${what//$'\n'/ }"
  next_action="${next_action//$'\n'/ }"
  blocker="${blocker//$'\n'/ }"
  focus="${focus//$'\n'/ }"

  # Build new Resume state block
  local resume_block
  resume_block="$(cat <<EOF
## Resume state
_Overwritten by \`agentboard checkpoint\` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** ${today_str} by ${agent}
- **What just happened:** ${what}
- **Current focus:** ${focus}
- **Next action:** ${next_action}
- **Blockers:** ${blocker}
EOF
  )"

  # Build new Progress log entry
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

  _checkpoint_write_resume_state "$stream_file" "$resume_block"
  _checkpoint_prepend_progress_entry "$stream_file" "$log_entry"
  replace_frontmatter_line "$stream_file" "updated_at" "$today_str"

  ok "Checkpoint saved to $stream_file"
  say "  ${C_DIM}next:${C_RESET} ${next_action}"
  say "  ${C_DIM}Ready for handoff — run: agentboard handoff ${slug}${C_RESET}"
}

# Overwrite or insert the ## Resume state section. If the section exists, it's
# replaced in place (preserving everything before and after). If it's missing,
# insert before ## Progress log, or before ## Next action, or append.
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

# Prepend a dated entry to ## Progress log (creating the section if absent),
# then keep only the 10 most-recent entries. Entries are delimited by leading
# date lines (YYYY-MM-DD ...) at column 0.
_checkpoint_prepend_progress_entry() {
  local file="$1" entry="$2"
  local tmp entry_file
  tmp="$(mktemp)"
  entry_file="$(mktemp)"
  printf '%s\n' "$entry" > "$entry_file"

  if ! grep -q '^## Progress log[[:space:]]*$' "$file"; then
    {
      cat "$file"
      printf '\n## Progress log\n_Append-only. Auto-trimmed by `agentboard checkpoint` to last 10 entries._\n\n'
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
      # Insert the new entry before existing log lines. The entry starts with
      # a YYYY-MM-DD date line so it counts as entry 1 for the 10-entry cap.
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
      # Count entry headers (YYYY-MM-DD ... at column 0, non-indented)
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
