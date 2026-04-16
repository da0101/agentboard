cmd_migrate() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local apply=0
  case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) die "Usage: agentboard migrate [--apply]" ;;
  esac

  local repos_file="./.platform/repos.md"
  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"

  printf '\n%s%sagentboard migrate%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if (( apply )); then
    printf '%sApply mode — legacy files will be upgraded in place when inference is safe.%s\n' "$C_DIM" "$C_RESET"
  else
    printf '%sPreview mode — no files will be changed. Re-run with --apply to write upgrades.%s\n' "$C_DIM" "$C_RESET"
  fi
  say

  local stream_rows=""
  [[ -f "$active" ]] && stream_rows="$(stream_rows_from_active "$active")"

  local migrated=0 skipped=0
  local stream_file slug row row_type row_status row_agent row_updated
  while IFS= read -r stream_file; do
    [[ -n "$stream_file" ]] || continue
    is_legacy_stream_file "$stream_file" || continue
    slug="$(basename "$stream_file" .md)"

    row="$(printf '%s\n' "$stream_rows" | awk -F'|' -v slug="$slug" '$1 == slug { print; exit }')"
    row_type=""; row_status=""; row_agent=""; row_updated=""
    [[ -n "$row" ]] && IFS='|' read -r _ row_type row_status row_agent row_updated <<< "$row"

    local stream_type stream_status agent_owner created_at updated_at closure_approved domain_slugs repo_ids
    stream_type="$(normalize_kebab_value "$(legacy_stream_value "$stream_file" "Type")")"
    stream_status="$(normalize_kebab_value "$(legacy_stream_value "$stream_file" "Status")")"
    agent_owner="$(trim "$(legacy_stream_value "$stream_file" "Agent")")"
    created_at="$(trim "$(legacy_stream_value "$stream_file" "Started")")"
    updated_at="${row_updated:-$created_at}"
    closure_approved="$(legacy_closure_approved "$stream_file")"

    [[ -z "$stream_type" ]] && stream_type="${row_type:-feature}"
    [[ -z "$stream_status" ]] && stream_status="${row_status:-planning}"
    [[ -z "$agent_owner" ]] && agent_owner="${row_agent:-codex}"
    [[ -z "$created_at" ]] && created_at="$(today)"
    [[ -z "$updated_at" ]] && updated_at="$created_at"

    domain_slugs="$(infer_stream_domain_slugs "$slug")"
    if [[ -z "$domain_slugs" ]]; then
      warn "Skipping legacy stream '$slug' — could not infer domain_slugs safely"
      skipped=$((skipped + 1))
      continue
    fi

    repo_ids="$(infer_stream_repo_ids "$stream_file" "$repos_file" "$domain_slugs" | unique_nonempty_lines)"
    if [[ -z "$repo_ids" ]]; then
      warn "Skipping legacy stream '$slug' — could not infer repo_ids safely"
      skipped=$((skipped + 1))
      continue
    fi

    local fm
    fm="$(cat <<EOF
---
stream_id: $(canonical_stream_id "$slug")
slug: $slug
type: $stream_type
status: $stream_status
agent_owner: $agent_owner
domain_slugs: $(frontmatter_inline_array <<< "$domain_slugs")
repo_ids: $(frontmatter_inline_array <<< "$repo_ids")
created_at: $created_at
updated_at: $updated_at
closure_approved: $closure_approved
---
EOF
)"

    if (( apply )); then
      local tmp
      tmp="$(mktemp)"
      printf '%s\n\n' "$fm" > "$tmp"
      cat "$stream_file" >> "$tmp"
      mv "$tmp" "$stream_file"
      ok "Migrated legacy stream: .platform/work/${slug}.md"
    else
      say "  ~ would migrate stream '$slug' -> domain_slugs=$(frontmatter_inline_array <<< "$domain_slugs") repo_ids=$(frontmatter_inline_array <<< "$repo_ids")"
    fi
    migrated=$((migrated + 1))
  done < <(stream_files)

  local domain_file
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    is_legacy_domain_file "$domain_file" || continue
    slug="$(basename "$domain_file" .md)"

    local repo_ids
    repo_ids="$(infer_domain_repo_ids "$domain_file" "$repos_file" | unique_nonempty_lines)"
    if [[ -z "$repo_ids" ]]; then
      warn "Skipping legacy domain '$slug' — could not infer repo_ids safely"
      skipped=$((skipped + 1))
      continue
    fi

    local fm
    fm="$(cat <<EOF
---
domain_id: $(canonical_domain_id "$slug")
slug: $slug
status: active
repo_ids: $(frontmatter_inline_array <<< "$repo_ids")
related_domain_slugs: []
created_at: $(today)
updated_at: $(today)
---
EOF
)"

    if (( apply )); then
      local tmp
      tmp="$(mktemp)"
      printf '%s\n\n' "$fm" > "$tmp"
      cat "$domain_file" >> "$tmp"
      mv "$tmp" "$domain_file"
      ok "Migrated legacy domain: .platform/domains/${slug}.md"
    else
      say "  ~ would migrate domain '$slug' -> repo_ids=$(frontmatter_inline_array <<< "$repo_ids")"
    fi
    migrated=$((migrated + 1))
  done < <(domain_files)

  if [[ -f "$brief" ]] && is_legacy_brief_file "$brief"; then
    warn "Legacy multi-stream BRIEF detected — leaving it as-is. Run 'agentboard brief-upgrade <stream-slug> --apply' when you want a modern single-stream brief."
    skipped=$((skipped + 1))
  fi

  say
  if (( apply )); then
    printf '%s%sMigration complete%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  else
    printf '%s%sMigration preview complete%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  fi
  printf '  migrated: %s%d%s   skipped: %s%d%s\n' \
    "$C_BOLD" "$migrated" "$C_RESET" \
    "$C_BOLD" "$skipped" "$C_RESET"
  say
}

cmd_brief_upgrade() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local apply=0 requested_slug=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        apply=1
        shift
        ;;
      -*)
        die "Usage: agentboard brief-upgrade [stream-slug] [--apply]"
        ;;
      *)
        [[ -z "$requested_slug" ]] || die "Usage: agentboard brief-upgrade [stream-slug] [--apply]"
        requested_slug="$1"
        shift
        ;;
    esac
  done

  local brief="./.platform/work/BRIEF.md"
  local active="./.platform/work/ACTIVE.md"
  local repos_file="./.platform/repos.md"
  local project_name stream_rows rows_count slug type status agent updated generated

  [[ -f "$brief" ]] || die "$brief not found."
  [[ -f "$active" ]] || die "$active not found."

  if [[ ! -f "$brief" ]] || { ! is_legacy_brief_file "$brief" && ! brief_is_placeholder "$brief"; }; then
    die "work/BRIEF.md is already in modern format. Edit it directly instead of using brief-upgrade."
  fi

  project_name="$(basename "$(pwd)")"
  stream_rows="$(stream_rows_from_active "$active")"
  rows_count=0
  [[ -n "$stream_rows" ]] && rows_count="$(printf '%s\n' "$stream_rows" | awk 'NF { c++ } END { print c + 0 }')"

  if [[ -n "$requested_slug" ]]; then
    local matched_row stream_file
    matched_row="$(printf '%s\n' "$stream_rows" | awk -F'|' -v slug="$requested_slug" '$1 == slug { print; exit }')"
    stream_file="./.platform/work/${requested_slug}.md"
    [[ -f "$stream_file" ]] || die "Stream file .platform/work/${requested_slug}.md not found."
    if [[ -n "$matched_row" ]]; then
      IFS='|' read -r slug type status agent updated <<< "$matched_row"
    else
      slug="$requested_slug"
      type="$(frontmatter_value "$stream_file" "type")"
      status="$(frontmatter_value "$stream_file" "status")"
      agent="$(frontmatter_value "$stream_file" "agent_owner")"
      updated="$(frontmatter_value "$stream_file" "updated_at")"
    fi
  else
    if (( rows_count == 1 )); then
      IFS='|' read -r slug type status agent updated <<< "$stream_rows"
    else
      warn "brief-upgrade needs a target stream when more than one stream is active."
      if is_legacy_brief_file "$brief"; then
        local legacy_slug
        printf '%s\n' "  Legacy brief streams:" >&2
        while IFS= read -r legacy_slug; do
          [[ -n "$legacy_slug" ]] || continue
          printf '  - %s\n' "$legacy_slug" >&2
        done < <(legacy_brief_stream_slugs "$brief")
      elif [[ -n "$stream_rows" ]]; then
        printf '%s\n' "  Active streams:" >&2
        printf '%s\n' "$stream_rows" | awk -F'|' '{ printf "  - %s (%s, %s)\n", $1, $2, $3 }' >&2
      fi
      die "Usage: agentboard brief-upgrade <stream-slug> [--apply]"
    fi
  fi

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."

  generated="$(render_brief_from_stream "$project_name" "$slug" "${status:-planning}" "$stream_file" "$repos_file")"

  printf '\n%s%sagentboard brief-upgrade%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if (( apply )); then
    printf '%sApply mode — work/BRIEF.md will be rewritten for stream %s.%s\n' "$C_DIM" "$slug" "$C_RESET"
    printf '%s\n' "$generated" > "$brief"
    ok "Rewrote work/BRIEF.md for stream '$slug'"
    say
    return 0
  fi

  printf '%sPreview mode — no files will be changed. Re-run with --apply to write the upgraded brief.%s\n' "$C_DIM" "$C_RESET"
  printf '  target stream: %s\n' "$slug"
  say
  printf '%s\n' "$generated"
  say
}

