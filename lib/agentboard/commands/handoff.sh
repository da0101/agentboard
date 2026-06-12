# Resolve the requested (or sole active) stream row into cmd_handoff locals
# slug, type, status, agent, updated. Reads requested_slug and rows from
# cmd_handoff dynamic scope. Call only from cmd_handoff.
_handoff_select_stream() {
  if [[ -n "$requested_slug" ]]; then
    local matched_row=""
    matched_row="$(printf '%s\n' "$rows" | awk -F'|' -v slug="$requested_slug" '$1 == slug { print; exit }')"
    if [[ -n "$matched_row" ]]; then
      IFS='|' read -r slug type status agent updated <<< "$matched_row"
    else
      local stream_file="./.platform/work/${requested_slug}.md"
      [[ -f "$stream_file" ]] || die "Stream '$requested_slug' is not active and .platform/work/${requested_slug}.md does not exist."
      slug="$requested_slug"
      type="$(frontmatter_value "$stream_file" "type")"
      status="$(frontmatter_value "$stream_file" "status")"
      agent="$(frontmatter_value "$stream_file" "agent_owner")"
      updated="$(frontmatter_value "$stream_file" "updated_at")"
    fi
  else
    local count=0
    [[ -n "$rows" ]] && count="$(printf '%s\n' "$rows" | awk 'NF { c++ } END { print c + 0 }')"
    if (( count == 0 )); then
      die "No active streams found. Use 'ab new-stream ...' or update .platform/work/ACTIVE.md first."
    elif (( count > 1 )); then
      warn "Multiple active streams found:"
      printf '%s\n' "$rows" | awk -F'|' '{ printf "  - %s (%s, %s)\n", $1, $2, $3 }' >&2
      die "Usage: ab handoff <stream-slug>"
    else
      IFS='|' read -r slug type status agent updated <<< "$rows"
    fi
  fi
}

# Print the handoff header (identity, staleness warning, branch hint) and set
# next_action, build_excerpt, current_excerpt, do_not_load in cmd_handoff scope.
_handoff_print_header() {
  next_action="$(stream_next_action "$stream_file")"
  [[ -n "$next_action" ]] || next_action="(not set)"

  build_excerpt="$(markdown_section_excerpt "$brief" "## What we're building")"
  current_excerpt="$(markdown_section_excerpt "$brief" "## Current state")"
  do_not_load="$(sed -n 's/^\*\*Do not load:\*\* //p' "$brief")"
  do_not_load="${do_not_load%%$'\n'*}"

  printf '\n%s%sab handoff%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  stream: %s%s%s\n' "$C_BOLD" "$slug" "$C_RESET"
  printf '  id:     %s\n' "$(frontmatter_value "$stream_file" "stream_id")"
  printf '  type:   %s\n' "${type:-unknown}"
  printf '  status: %s\n' "${status:-unknown}"
  printf '  owner:  %s\n' "${agent:-unknown}"
  printf '  updated:%s %s\n' "${updated:+ }" "${updated:-unknown}"

  local _today _stream_updated
  _today="$(today)"
  _stream_updated="$(frontmatter_value "$stream_file" "updated_at")"
  if [[ -n "$_stream_updated" && "$_stream_updated" != "$_today" ]] && ! is_placeholder_value "$_stream_updated"; then
    printf '  %s⚠%s  %sStream state last updated %s — resume state may be stale%s\n' \
      "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$_stream_updated" "$C_RESET"
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
      local _recent_commits
      _recent_commits="$(git --no-pager log --oneline --max-count=10 --since="$_stream_updated" 2>/dev/null || true)"
      if [[ -n "$_recent_commits" ]]; then
        printf '  %sCommits since last checkpoint:%s\n' "$C_DIM" "$C_RESET"
        local _cline
        while IFS= read -r _cline; do
          printf '    %s%s%s\n' "$C_DIM" "$_cline" "$C_RESET"
        done <<< "$_recent_commits"
      else
        printf '  %s(no commits since last checkpoint — context may be genuinely stale)%s\n' \
          "$C_DIM" "$C_RESET"
      fi
    fi
    printf '\n'
  fi

  local _git_branch _base_branch
  _git_branch="$(frontmatter_value "$stream_file" "git_branch")"
  _base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  if [[ -n "$_git_branch" ]] && ! is_placeholder_value "$_git_branch"; then
    printf '  branch: %s%s%s' "$C_BOLD" "$_git_branch" "$C_RESET"
    [[ -n "$_base_branch" ]] && ! is_placeholder_value "$_base_branch" && \
      printf '  %s(forked from %s)%s' "$C_DIM" "$_base_branch" "$C_RESET"
    printf '\n'
    printf '  %s⚡ git checkout %s%s\n' "$C_DIM" "$_git_branch" "$C_RESET"
  fi
  say
}

# Apply the token budget to the stream domains. Sets brief_tokens,
# stream_tokens, running_tokens, included_domains, skipped_domains in
# cmd_handoff scope.
_handoff_compute_domains() {
  brief_tokens="$(estimate_tokens_for_file "$brief")"
  stream_tokens="$(estimate_tokens_for_file "$stream_file")"
  running_tokens=$(( brief_tokens + stream_tokens ))

  local -a domain_token_cache=()
  local domain_slug domain_file domain_tokens first_domain=1
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    domain_file="./.platform/domains/${domain_slug}.md"
    domain_tokens="$(estimate_tokens_for_file "$domain_file")"
    if (( budget > 0 )) && (( first_domain == 0 )) && (( running_tokens + domain_tokens > budget )); then
      skipped_domains+=("${domain_slug}|${domain_tokens}")
    else
      included_domains+=("${domain_slug}|${domain_tokens}")
      running_tokens=$(( running_tokens + domain_tokens ))
      first_domain=0
    fi
  done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
}

# Print the load order (with optional budget annotations, domain staleness
# checks) and any budget-skipped domains. Reads cmd_handoff dynamic scope.
_handoff_print_load_order() {
  if (( budget > 0 )); then
    printf '%sLoad in this order%s %s(budget %s tokens, using ~%d)%s\n' \
      "$C_BOLD" "$C_RESET" "$C_DIM" "$budget_arg" "$running_tokens" "$C_RESET"
  else
    printf '%sLoad in this order:%s\n' "$C_BOLD" "$C_RESET"
  fi
  printf '  1. .platform/work/BRIEF.md%s\n' "$( (( budget > 0 )) && printf '  (~%d)' "$brief_tokens" )"
  printf '  2. .platform/work/%s.md%s\n' "$slug" "$( (( budget > 0 )) && printf '  (~%d)' "$stream_tokens" )"
  local entry idx=3 e_slug e_tokens
  local _stream_created_at
  _stream_created_at="$(frontmatter_value "$stream_file" "created_at")"
  for entry in "${included_domains[@]}"; do
    e_slug="${entry%%|*}"; e_tokens="${entry#*|}"
    printf '  %d. .platform/domains/%s.md%s\n' "$idx" "$e_slug" \
      "$( (( budget > 0 )) && printf '  (~%d)' "$e_tokens" )"
    # Staleness check: flag if domain hasn't been touched since stream started
    if command -v git >/dev/null 2>&1 && [[ -n "$_stream_created_at" ]] \
        && ! is_placeholder_value "$_stream_created_at"; then
      local _dfile="./.platform/domains/${e_slug}.md"
      local _ddate
      git_file_has_worktree_changes "$_dfile" && { idx=$((idx + 1)); continue; }
      _ddate="$(_handoff_domain_git_date "$_dfile")"
      if [[ -n "$_ddate" && "$_ddate" < "$_stream_created_at" ]]; then
        printf '     %s⚠ domain last updated %s — may not reflect work done in this stream%s\n' \
          "$C_YELLOW" "$_ddate" "$C_RESET"
      fi
    fi
    idx=$((idx + 1))
  done
  say

  if (( ${#skipped_domains[@]} > 0 )); then
    printf '%sSkipped (budget tight):%s\n' "$C_BOLD" "$C_RESET"
    for entry in "${skipped_domains[@]}"; do
      e_slug="${entry%%|*}"; e_tokens="${entry#*|}"
      printf '  - .platform/domains/%s.md  %s(~%d tokens)%s\n' \
        "$e_slug" "$C_DIM" "$e_tokens" "$C_RESET"
    done
    say
  fi
}

cmd_handoff() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local requested_slug="" budget_arg="" budget=0 _show_snippets=1
  if [[ -n "${1:-}" && "${1:0:2}" != "--" ]]; then
    requested_slug="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --budget)
        [[ -n "${2:-}" ]] || die "handoff requires a value after --budget"
        budget_arg="$2"
        budget="$(parse_token_budget "$2")" || die "Invalid --budget '$2' (use e.g. 4000 or 4k)"
        shift 2 ;;
      --no-snippets) _show_snippets=0; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: ab handoff [<stream-slug>] [--budget <N|Nk>] [--no-snippets]

Prints the load order and context snippets for the next agent's context pack.
Context snippets are auto-searched from domain files using stream + domain slug
keywords — so the agent can read targeted excerpts instead of loading full files.
--budget trims secondary domains when the estimated token total exceeds the
limit. Estimation uses bytes/4 as a rough heuristic (zero dependencies).
--no-snippets skips the context snippets section (load-order only).
EOF
        return 0 ;;
      *) die "Unknown flag for handoff: $1" ;;
    esac
  done

  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"
  local repos_file="./.platform/repos.md"
  [[ -f "$active" ]] || die "$active not found."
  [[ -f "$brief" ]] || die "$brief not found."

  local rows
  rows="$(stream_rows_from_active "$active")"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"

  local slug="" type="" status="" agent="" updated=""
  _handoff_select_stream

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."

  local next_action build_excerpt current_excerpt do_not_load
  local brief_tokens stream_tokens running_tokens
  local -a included_domains=() skipped_domains=()

  _handoff_print_header
  _handoff_compute_domains
  _handoff_print_load_order
  _handoff_print_snippets
  _handoff_print_repo_scope
  _handoff_print_resume
  _handoff_print_footer
}
