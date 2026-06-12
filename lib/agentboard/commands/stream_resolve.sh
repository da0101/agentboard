cmd_resolve() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: ab resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>"

  local repos_file="./.platform/repos.md"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"

  local stream_file=""
  if [[ -f "./.platform/work/${target}.md" ]]; then
    stream_file="./.platform/work/${target}.md"
  else
    stream_file="$(stream_file_by_id "$target" 2>/dev/null || true)"
  fi

  if [[ -n "$stream_file" ]]; then
    local slug type stream_id repo_ids domain_slugs
    slug="$(basename "$stream_file" .md)"
    type="$(frontmatter_value "$stream_file" "type")"
    stream_id="$(frontmatter_value "$stream_file" "stream_id")"
    repo_ids="$(frontmatter_value "$stream_file" "repo_ids")"
    domain_slugs="$(frontmatter_value "$stream_file" "domain_slugs")"

    printf '\n%s%sab resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "stream"
    printf '  id:   %s\n' "${stream_id:-$(canonical_stream_id "$slug")}"
    printf '  slug: %s\n' "$slug"
    printf '  file: .platform/work/%s.md\n' "$slug"
    printf '  kind: %s\n' "${type:-unknown}"
    if [[ -n "$(inline_array_items "$domain_slugs")" ]]; then
      printf '  domains: %s\n' "$(inline_array_items "$domain_slugs" | join_lines_comma)"
    fi
    if [[ -n "$(inline_array_items "$repo_ids")" ]]; then
      printf '  repos:   %s\n' "$(inline_array_items "$repo_ids" | join_lines_comma)"
    fi
    say
    return 0
  fi

  local domain_file=""
  if [[ -f "./.platform/domains/${target}.md" ]]; then
    domain_file="./.platform/domains/${target}.md"
  else
    domain_file="$(domain_file_by_id "$target" 2>/dev/null || true)"
  fi

  if [[ -n "$domain_file" ]]; then
    local slug domain_id repo_ids
    slug="$(basename "$domain_file" .md)"
    domain_id="$(frontmatter_value "$domain_file" "domain_id")"
    repo_ids="$(frontmatter_value "$domain_file" "repo_ids")"

    printf '\n%s%sab resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "domain"
    printf '  id:   %s\n' "${domain_id:-$(canonical_domain_id "$slug")}"
    printf '  slug: %s\n' "$slug"
    printf '  file: .platform/domains/%s.md\n' "$slug"
    if [[ -n "$(inline_array_items "$repo_ids")" ]]; then
      printf '  repos: %s\n' "$(inline_array_items "$repo_ids" | join_lines_comma)"
    fi
    say
    return 0
  fi

  local repo_row=""
  repo_row="$(repo_row_for_id "$repo_rows" "$target" 2>/dev/null || true)"
  if [[ -n "$repo_row" ]]; then
    local repo_name repo_path repo_stack repo_ref
    IFS='|' read -r repo_name repo_path repo_stack repo_ref <<< "$repo_row"

    printf '\n%s%sab resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "repo"
    printf '  id:   %s\n' "$repo_name"
    printf '  path: %s\n' "${repo_path:-unknown}"
    printf '  stack:%s %s\n' "${repo_stack:+ }" "${repo_stack:-unknown}"
    if [[ -n "$repo_ref" ]] && ! is_placeholder_value "$repo_ref"; then
      printf '  deep reference: .platform/%s\n' "$repo_ref"
    fi
    say
    return 0
  fi

  if [[ "$target" == "repo-primary" ]]; then
    printf '\n%s%sab resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "repo"
    printf '  id:   %s\n' "repo-primary"
    printf '  path: %s\n' "."
    printf '  stack: %s\n' "(see .platform/repos.md or activation output)"
    say
    return 0
  fi

  die "Could not resolve '$target' as a stream, domain, or repo id."
}

cmd_current_stream() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local explicit_stream="" session_id="" remember=0 quiet=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stream)
        [[ -n "${2:-}" ]] || die "current-stream requires a value after --stream"
        explicit_stream="$2"
        shift 2
        ;;
      --session-id)
        [[ -n "${2:-}" ]] || die "current-stream requires a value after --session-id"
        session_id="$2"
        shift 2
        ;;
      --remember)
        remember=1
        shift
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: ab current-stream [--stream <slug>] [--session-id <id>] [--remember] [--quiet]

Resolve the canonical current stream slug using this order:
  1. explicit --stream
  2. AGENTBOARD_STREAM
  3. remembered session-id mapping
  4. work/BRIEF.md primary stream
  5. the only active stream

Returns non-zero if resolution is ambiguous or no stream can be inferred.
EOF
        return 0
        ;;
      *)
        die "Unknown flag for current-stream: $1"
        ;;
    esac
  done

  local stream_slug
  stream_slug="$(resolve_current_stream "$explicit_stream" "$session_id" 2>/dev/null || true)"
  [[ -n "$stream_slug" ]] || return 1

  if (( remember )) && [[ -n "$session_id" ]]; then
    remember_session_stream "$session_id" "$stream_slug"
  fi

  if (( quiet )); then
    printf '%s\n' "$stream_slug"
  else
    printf '\n%s%sab current-stream%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  stream: %s\n' "$stream_slug"
    if [[ -n "$session_id" ]]; then
      printf '  session: %s\n' "$session_id"
    fi
    say
  fi
}

cmd_next_action() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local stream_slug="${1:-}" session_id="" quiet=0
  if [[ -n "$stream_slug" && "${stream_slug:0:2}" == "--" ]]; then
    stream_slug=""
  else
    shift || true
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id)
        [[ -n "${2:-}" ]] || die "next-action requires a value after --session-id"
        session_id="$2"
        shift 2
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: ab next-action [stream-slug] [--session-id <id>] [--quiet]

Print the canonical next action from the stream's Resume state, falling back to
the legacy ## Next action section when needed.
EOF
        return 0
        ;;
      *)
        die "Unknown flag for next-action: $1"
        ;;
    esac
  done

  if [[ -z "$stream_slug" ]]; then
    stream_slug="$(resolve_current_stream "" "$session_id" 2>/dev/null || true)"
  fi
  [[ -n "$stream_slug" ]] || return 1

  local stream_file="./.platform/work/${stream_slug}.md"
  [[ -f "$stream_file" ]] || die "Stream file not found: $stream_file"

  local next_action
  next_action="$(stream_next_action "$stream_file")"
  [[ -n "$next_action" ]] || return 1

  if (( quiet )); then
    printf '%s\n' "$next_action"
  else
    printf '\n%s%sab next-action%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  stream: %s\n' "$stream_slug"
    printf '  next:   %s\n' "$next_action"
    say
  fi
}
