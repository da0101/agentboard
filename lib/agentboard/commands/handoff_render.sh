# Print last N Reason events for a stream from events.jsonl.
# Used by cmd_handoff to show the next agent what was done and why.
_handoff_render_reasons() {
  local slug="$1" max="${2:-5}" log="./.platform/events.jsonl"
  [[ -f "$log" ]] || return 0
  awk -v target="$slug" -v max="$max" '
    function extract(s, key,    re, val) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
      if (match(s, re)) {
        val = substr(s, RSTART, RLENGTH)
        sub("^\"" key "\"[[:space:]]*:[[:space:]]*\"", "", val)
        sub("\"$", "", val)
        return val
      }
      return ""
    }
    {
      hook   = extract($0, "hook_event_name")
      stream = extract($0, "stream")
      if (hook == "Reason" && (stream == target || stream == "")) {
        lines[++n] = $0
      }
    }
    END {
      if (n == 0) exit
      start = (n > max) ? n - max + 1 : 1
      for (i = start; i <= n; i++) {
        prov   = extract(lines[i], "provider")
        ts     = extract(lines[i], "ts")
        file   = extract(lines[i], "file")
        reason = extract(lines[i], "reason")
        date   = substr(ts, 1, 10)
        if (file != "")
          printf "  [%s %s] %s: %s\n", prov, date, file, reason
        else
          printf "  [%s %s] %s\n", prov, date, reason
      }
    }
  ' "$log"
}

# Return YYYY-MM-DD of the last git commit that touched a file, or "".
# Returns exit 0 always — safe to call without || true in set -e contexts.
_handoff_domain_git_date() {
  git log -1 --format="%ai" -- "$1" 2>/dev/null | awk '{print $1}' || true
}

# Print the context-snippets section. Relies on cmd_handoff dynamic scope:
# reads _show_snippets, slug, stream_file, included_domains, skipped_domains.
_handoff_print_snippets() {
  # ── Context snippets from domain files ──────────────────────────────────
  if (( _show_snippets )); then
    local -a _kw=()
    local _sp
    for _sp in $(printf '%s' "$slug" | tr '-' ' '); do
      case "$_sp" in a|an|the|and|for|in|on|of|to|is|be|do|it|by|or|at|if|new|add|fix|update|refactor) continue ;; esac
      _kw+=("$_sp")
    done
    local _ds2
    while IFS= read -r _ds2; do
      [[ -z "$_ds2" ]] && continue
      for _sp in $(printf '%s' "$_ds2" | tr '-' ' '); do
        case "$_sp" in a|an|the|and|for|in|on|of|to|is|be|do|it|by|or|at|if|new|add|fix|update|refactor) continue ;; esac
        _kw+=("$_sp")
      done
    done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")

    local -a _all_dom_entries=()
    [[ ${#included_domains[@]} -gt 0 ]] && _all_dom_entries+=("${included_domains[@]}")
    [[ ${#skipped_domains[@]} -gt 0 ]]  && _all_dom_entries+=("${skipped_domains[@]}")

    if (( ${#_kw[@]} > 0 && ${#_all_dom_entries[@]} > 0 )); then
      local _kw_pat; _kw_pat="$(IFS='|'; printf '%s' "${_kw[*]}")"
      local _use_rg_s=0; command -v rg >/dev/null 2>&1 && _use_rg_s=1 || true
      local _snip_found=0 _s_entry _s_slug _s_tok _s_file _s_matches

      printf '%sContext snippets%s %s(keywords: %s)%s\n' \
        "$C_BOLD" "$C_RESET" "$C_DIM" "${_kw[*]}" "$C_RESET"

      for _s_entry in "${_all_dom_entries[@]}"; do
        _s_slug="${_s_entry%%|*}"; _s_tok="${_s_entry#*|}"
        _s_file="./.platform/domains/${_s_slug}.md"
        [[ -f "$_s_file" ]] || continue
        if (( _use_rg_s )); then
          _s_matches="$(rg -i -C 2 --color=never --no-heading --no-context-separator \
            -e "$_kw_pat" "$_s_file" 2>/dev/null | awk 'NR<=25 && $0 != "--"' || true)"
        else
          _s_matches="$(grep -i -E -C 2 --color=never "$_kw_pat" "$_s_file" 2>/dev/null | awk 'NR<=25 && $0 != "--"' || true)"
        fi
        [[ -z "$_s_matches" ]] && continue
        # (( var++ )) returns the pre-increment value, so it exits 1 under
        # set -e when the counter is 0. Assignment form is errexit-safe.
        _snip_found=$((_snip_found + 1))
        printf '\n  %s%s%s %s(~%d tokens full file)%s\n' \
          "$C_CYAN" "$_s_file" "$C_RESET" "$C_DIM" "$_s_tok" "$C_RESET"
        printf '%s\n' "$_s_matches" | awk '{ print "  | " $0 }'
      done

      if (( _snip_found == 0 )); then
        printf '  %s(no domain file matches — load full files from the list above)%s\n' \
          "$C_DIM" "$C_RESET"
      else
        printf '\n  %sLoad full domain files only if these snippets are insufficient.%s\n' \
          "$C_DIM" "$C_RESET"
      fi
      say
    fi
  fi
}

# Print the repos-in-scope section. Reads stream_file and repo_rows from
# cmd_handoff dynamic scope.
_handoff_print_repo_scope() {
  local domain_slug
  local repo_scope=""
  repo_scope="$(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")"
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    local domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || continue
    repo_scope="${repo_scope}"$'\n'"$(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")"
  done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
  repo_scope="$(printf '%s\n' "$repo_scope" | awk 'NF && !seen[$0]++')"

  if [[ -n "$repo_scope" ]]; then
    local repo_id repo_row repo_name repo_path repo_stack repo_ref
    printf '%sRepos in scope:%s\n' "$C_BOLD" "$C_RESET"
    while IFS= read -r repo_id; do
      [[ -z "$repo_id" ]] && continue
      repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
      if [[ -n "$repo_row" ]]; then
        IFS='|' read -r repo_name repo_path repo_stack repo_ref <<< "$repo_row"
        if [[ -n "$repo_ref" ]] && ! is_placeholder_value "$repo_ref"; then
          printf '  - %s -> %s (%s; deep ref: .platform/%s)\n' "$repo_id" "${repo_path:-unknown path}" "${repo_stack:-unknown stack}" "$repo_ref"
        else
          printf '  - %s -> %s (%s)\n' "$repo_id" "${repo_path:-unknown path}" "${repo_stack:-unknown stack}"
        fi
      elif [[ "$repo_id" == "repo-primary" ]]; then
        printf '  - %s -> . (current repo)\n' "$repo_id"
      else
        printf '  - %s -> (not found in .platform/repos.md)\n' "$repo_id"
      fi
    done <<< "$repo_scope"
    say
  fi
}

# Print the Resume state block (or the BRIEF.md fallback). Reads stream_file,
# slug, next_action, build_excerpt, current_excerpt, do_not_load from
# cmd_handoff dynamic scope.
_handoff_print_resume() {
  local r_updated r_what r_focus r_next r_blockers
  r_updated="$(stream_resume_field "$stream_file" "Last updated")"
  r_what="$(stream_resume_field "$stream_file" "What just happened")"
  r_focus="$(stream_resume_field "$stream_file" "Current focus")"
  r_next="$(stream_resume_field "$stream_file" "Next action")"
  r_blockers="$(stream_resume_field "$stream_file" "Blockers")"

  _is_resume_placeholder() {
    local v="$1"
    [[ -z "$v" ]] && return 0
    [[ "$v" == "—" ]] && return 0
    [[ "$v" == "_not set_" ]] && return 0
    [[ "$v" == "— by —" ]] && return 0
    return 1
  }

  if ! _is_resume_placeholder "$r_what" || ! _is_resume_placeholder "$r_next"; then
    printf '%sResume state%s %s(from %s.md § Resume state)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$slug" "$C_RESET"
    _is_resume_placeholder "$r_updated" || printf '  Last updated:       %s\n' "$r_updated"
    _is_resume_placeholder "$r_what"    || printf '  What just happened: %s\n' "$r_what"
    _is_resume_placeholder "$r_focus"   || printf '  Current focus:      %s\n' "$r_focus"
    _is_resume_placeholder "$r_next"    || printf '  Next action:        %s%s%s\n' "$C_BOLD" "$r_next" "$C_RESET"
    _is_resume_placeholder "$r_blockers" || printf '  Blockers:           %s\n' "$r_blockers"
    say
  else
    printf '%sNext action:%s %s\n' "$C_BOLD" "$C_RESET" "$next_action"
    if [[ -n "$build_excerpt" ]]; then
      say
      printf '%sWhat we are building:%s\n' "$C_BOLD" "$C_RESET"
      printf '%s\n' "$build_excerpt"
    fi
    if [[ -n "$current_excerpt" ]]; then
      say
      printf '%sCurrent state:%s\n' "$C_BOLD" "$C_RESET"
      printf '%s\n' "$current_excerpt"
    fi
    if [[ -n "$do_not_load" && "$do_not_load" != "_TODO_" ]]; then
      say
      printf '%sDo not load:%s %s\n' "$C_BOLD" "$C_RESET" "$do_not_load"
    fi
    say
  fi
}

# Print recent reasoning plus the closing instructions. Reads slug from
# cmd_handoff dynamic scope.
_handoff_print_footer() {
  local _reasons_out
  _reasons_out="$(_handoff_render_reasons "$slug" 5)"
  if [[ -n "$_reasons_out" ]]; then
    printf '%sRecent reasoning%s %s(last 5 ab log-reason calls for this stream)%s\n' \
      "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '%s\n' "$_reasons_out"
    say
  fi

  printf '%sFor the agent reading this:%s\n' "$C_BOLD" "$C_RESET"
  printf '  1. Load BRIEF.md + stream file. Check context snippets above — load full domain files only if insufficient.\n'
  printf '  2. Read the stream file '"'"'s "## Resume state" block first — it is the compact "where we are".\n'
  printf '  3. Confirm you understand Next action, then continue from there.\n'
  printf '  4. Before ending your session or switching providers, run:\n'
  printf '     %sab checkpoint %s --what "..." --next "..."%s\n' "$C_BOLD" "$slug" "$C_RESET"
  say
}
