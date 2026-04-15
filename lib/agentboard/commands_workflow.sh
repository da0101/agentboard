cmd_sync() {
  local script="./.platform/scripts/sync-context.sh"
  [[ -x "$script" ]] || die "$script not found or not executable. Run 'agentboard init' first."
  "$script" "$@"
}

cmd_claim() {
  local active="./.platform/sessions/ACTIVE.md"
  [[ -f "$active" ]] || die "$active not found. This project may be single-repo (no ACTIVE.md needed)."
  local task="${1:-}"
  [[ -n "$task" ]] || die "Usage: agentboard claim \"<task summary>\""
  local agent="${AGENTBOARD_AGENT:-$USER@$(hostname -s)}"
  local ts; ts="$(date '+%Y-%m-%d %H:%M')"
  local repo; repo="$(basename "$(pwd)")"
  local row="| $ts | $agent | $repo | — | $task | ~30min | active |"
  printf '%s\n' "$row" >> "$active"
  ok "Claimed: $task"
}

cmd_release() {
  local active="./.platform/sessions/ACTIVE.md"
  [[ -f "$active" ]] || die "$active not found."
  local agent="${AGENTBOARD_AGENT:-$USER@$(hostname -s)}"
  local tmp; tmp="$(mktemp)"
  grep -v "| $agent |" "$active" > "$tmp" || true
  mv "$tmp" "$active"
  ok "Released all claims for $agent"
}

cmd_log() {
  local log="./.platform/log.md"
  [[ -f "$log" ]] || die "$log not found. Run 'agentboard init' first."
  local line="${1:-}"
  [[ -n "$line" ]] || die "Usage: agentboard log \"<one line summary>\""
  local today_str; today_str="$(today)"
  local tmp; tmp="$(mktemp)"
  awk -v new="${today_str} — ${line}" '
    /^---$/ && !inserted { print; print ""; print new; inserted=1; next }
    { print }
  ' "$log" > "$tmp"
  mv "$tmp" "$log"
  ok "Logged: $line"
}

cmd_status() {
  local status="./.platform/STATUS.md"
  [[ -f "$status" ]] || die "$status not found. Run 'agentboard init' first."
  cat "$status"
}

cmd_doctor() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local errors=0 warnings=0
  local brief="./.platform/work/BRIEF.md"
  local active="./.platform/work/ACTIVE.md"
  local domains_dir="./.platform/domains"
  local sync_script="./.platform/scripts/sync-context.sh"
  local root_claude="./CLAUDE.md"
  local repos_file="./.platform/repos.md"
  local is_hub=0
  local repo_rows=""

  if [[ -f "$root_claude" ]] && grep -q "PLATFORM BRAINS HUB" "$root_claude"; then
    is_hub=1
  fi

  if [[ -f "$repos_file" ]]; then
    repo_rows="$(repo_rows_from_registry "$repos_file")"
  fi

  printf '\n%s%sagentboard doctor%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

  if [[ -f "$brief" ]]; then
    ok "work/BRIEF.md present"
  else
    warn "Missing .platform/work/BRIEF.md"
    errors=$((errors + 1))
  fi

  if [[ -f "$active" ]]; then
    ok "work/ACTIVE.md present"
  else
    warn "Missing .platform/work/ACTIVE.md"
    errors=$((errors + 1))
  fi

  if [[ -d "$domains_dir" ]]; then
    ok "domains/ directory present"
  else
    warn "Missing .platform/domains/"
    errors=$((errors + 1))
  fi

  if [[ -f "$root_claude" ]] && grep -q "NOT YET ACTIVATED" "$root_claude"; then
    ok "Activation stub detected — sync check skipped until activation"
  elif [[ -x "$sync_script" ]]; then
    local sync_output=""
    if sync_output="$("$sync_script" 2>&1)"; then
      ok "Root entry files in sync"
    else
      warn "Entry file drift detected by sync-context.sh"
      printf '%s\n' "$sync_output" >&2
      warnings=$((warnings + 1))
    fi
  else
    warn "sync-context.sh missing or not executable"
    warnings=$((warnings + 1))
  fi

  local seen_stream_ids="" seen_domain_ids=""
  local stream_file stream_slug stream_id
  while IFS= read -r stream_file; do
    [[ -n "$stream_file" ]] || continue
    stream_slug="$(basename "$stream_file" .md)"

    if is_legacy_stream_file "$stream_file"; then
      warn "Stream '$stream_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    stream_id="$(frontmatter_value "$stream_file" "stream_id")"

    if is_placeholder_value "$stream_id"; then
      warn "Stream '$stream_slug' is missing frontmatter key 'stream_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$stream_id" != "$(canonical_stream_id "$stream_slug")" ]]; then
      warn "Stream '$stream_slug' has non-canonical stream_id '$stream_id' (expected '$(canonical_stream_id "$stream_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_stream_ids" | grep -Fxq "$stream_id"; then
      warn "Duplicate stream_id '$stream_id' detected"
      errors=$((errors + 1))
    else
      seen_stream_ids="${seen_stream_ids}"$'\n'"$stream_id"
    fi
  done < <(stream_files)

  local domain_file domain_slug domain_id
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    domain_slug="$(basename "$domain_file" .md)"

    if is_legacy_domain_file "$domain_file"; then
      warn "Domain '$domain_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    domain_id="$(frontmatter_value "$domain_file" "domain_id")"

    if is_placeholder_value "$domain_id"; then
      warn "Domain '$domain_slug' is missing frontmatter key 'domain_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$domain_id" != "$(canonical_domain_id "$domain_slug")" ]]; then
      warn "Domain '$domain_slug' has non-canonical domain_id '$domain_id' (expected '$(canonical_domain_id "$domain_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_domain_ids" | grep -Fxq "$domain_id"; then
      warn "Duplicate domain_id '$domain_id' detected"
      errors=$((errors + 1))
    else
      seen_domain_ids="${seen_domain_ids}"$'\n'"$domain_id"
    fi
  done < <(domain_files)

  if [[ -f "$active" ]]; then
    local stream_rows=""
    stream_rows="$(stream_rows_from_active "$active" | awk -F'|' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')"

    if [[ -z "$stream_rows" ]]; then
      ok "No active streams registered"
    else
      local slug row_type row_status row_agent stream_file value
      while IFS='|' read -r slug row_type row_status row_agent; do
        [[ -z "$slug" ]] && continue
        stream_file="./.platform/work/${slug}.md"

        if [[ ! -f "$stream_file" ]]; then
          warn "Active stream '$slug' is missing file .platform/work/${slug}.md"
          errors=$((errors + 1))
          continue
        fi

        ok "Found stream file for '$slug'"

        if is_legacy_stream_file "$stream_file"; then
          local legacy_type legacy_status legacy_agent
          legacy_type="$(legacy_stream_value "$stream_file" "Type")"
          legacy_status="$(legacy_stream_value "$stream_file" "Status")"
          legacy_agent="$(legacy_stream_value "$stream_file" "Agent")"

          [[ -n "$legacy_type" && "$legacy_type" != "$row_type" ]] && {
            warn "Legacy stream '$slug' type mismatch: ACTIVE.md='$row_type' stream='$legacy_type'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_status" && "$legacy_status" != "$row_status" ]] && {
            warn "Legacy stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$legacy_status'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_agent" && "$legacy_agent" != "$row_agent" ]] && {
            warn "Legacy stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$legacy_agent'"
            warnings=$((warnings + 1))
          }
          continue
        fi

        local stream_keys=(stream_id slug type status agent_owner domain_slugs repo_ids created_at updated_at closure_approved)
        local key
        for key in "${stream_keys[@]}"; do
          value="$(frontmatter_value "$stream_file" "$key")"
          case "$key" in
            domain_slugs|repo_ids)
              if [[ -z "$(inline_array_items "$value")" ]]; then
                warn "Stream '$slug' is missing non-empty frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
            closure_approved)
              if [[ "$value" != "true" && "$value" != "false" ]]; then
                warn "Stream '$slug' has invalid closure_approved value '$value'"
                errors=$((errors + 1))
              fi
              ;;
            *)
              if is_placeholder_value "$value"; then
                warn "Stream '$slug' is missing frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
          esac
        done

        value="$(frontmatter_value "$stream_file" "slug")"
        if [[ -n "$value" && "$value" != "$slug" ]]; then
          warn "Stream '$slug' has slug '$value' in frontmatter"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "status")"
        if [[ -n "$value" && "$value" != "$row_status" ]]; then
          warn "Stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$value'"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "agent_owner")"
        if [[ -n "$row_agent" && "$row_agent" != "—" && -n "$value" && "$value" != "$row_agent" ]]; then
          warn "Stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$value'"
          warnings=$((warnings + 1))
        fi

        local repo_id repo_row
        while IFS= read -r repo_id; do
          [[ -z "$repo_id" ]] && continue
          repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
          if [[ -n "$repo_row" ]]; then
            continue
          fi
          if (( is_hub )) || [[ "$repo_id" != "repo-primary" ]]; then
            warn "Stream '$slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
            errors=$((errors + 1))
          fi
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")

        local domain_slug domain_file domain_value
        while IFS= read -r domain_slug; do
          [[ -z "$domain_slug" ]] && continue
          domain_file="./.platform/domains/${domain_slug}.md"
          if [[ ! -f "$domain_file" ]]; then
            warn "Stream '$slug' references missing domain file .platform/domains/${domain_slug}.md"
            errors=$((errors + 1))
            continue
          fi

          local domain_keys=(domain_id slug status repo_ids created_at updated_at)
          for key in "${domain_keys[@]}"; do
            domain_value="$(frontmatter_value "$domain_file" "$key")"
            case "$key" in
              repo_ids)
                if [[ -z "$(inline_array_items "$domain_value")" ]]; then
                  warn "Domain '$domain_slug' is missing non-empty frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
              *)
                if is_placeholder_value "$domain_value"; then
                  warn "Domain '$domain_slug' is missing frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
            esac
          done

          domain_value="$(frontmatter_value "$domain_file" "slug")"
          if [[ -n "$domain_value" && "$domain_value" != "$domain_slug" ]]; then
            warn "Domain '$domain_slug' has slug '$domain_value' in frontmatter"
            errors=$((errors + 1))
          fi

          while IFS= read -r repo_id; do
            [[ -z "$repo_id" ]] && continue
            repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
            if [[ -n "$repo_row" ]]; then
              continue
            fi
            if (( is_hub )) || [[ "$repo_id" != "repo-primary" ]]; then
              warn "Domain '$domain_slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
              errors=$((errors + 1))
            fi
          done < <(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
      done <<< "$stream_rows"
    fi
  fi

  if [[ -f "$brief" ]] && ! brief_is_placeholder "$brief"; then
    if is_legacy_brief_file "$brief"; then
      warn "work/BRIEF.md uses the legacy multi-stream format. Keep using it for now, or run 'agentboard brief-upgrade <stream-slug> --apply' when you settle on one active feature brief."
      warnings=$((warnings + 1))
    else
    local brief_stream=""
    brief_stream="$(sed -n 's/^\*\*Stream file:\*\* `work\/\([^`]*\)\.md`$/\1/p' "$brief")"
    brief_stream="${brief_stream%%$'\n'*}"
    if [[ -z "$brief_stream" ]]; then
      warn "work/BRIEF.md is missing a valid Stream file reference"
      errors=$((errors + 1))
    elif [[ ! -f "./.platform/work/${brief_stream}.md" ]]; then
      warn "work/BRIEF.md references missing stream file .platform/work/${brief_stream}.md"
      errors=$((errors + 1))
    fi

    local brief_domain_count=0
    local brief_domain
    while IFS= read -r brief_domain; do
      [[ -z "$brief_domain" ]] && continue
      brief_domain_count=$((brief_domain_count + 1))
      if [[ ! -f "./.platform/domains/${brief_domain}.md" ]]; then
        warn "work/BRIEF.md references missing domain file .platform/domains/${brief_domain}.md"
        errors=$((errors + 1))
      fi
    done < <(sed -n 's/^- `\.platform\/domains\/\([^` ]*\)\.md`.*$/\1/p' "$brief")

    if (( brief_domain_count == 0 )); then
      warn "work/BRIEF.md has no concrete domain references"
      errors=$((errors + 1))
    fi
    fi
  fi

  if (( is_hub )) && [[ -f "$repos_file" ]]; then
    if [[ -z "$repo_rows" ]]; then
      warn "Hub mode detected but .platform/repos.md has no repo rows"
      errors=$((errors + 1))
    else
      local seen_repo_ids=""
      local repo_name repo_path repo_stack repo_ref resolved_path
      while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
        [[ -z "$repo_name" ]] && continue

        if [[ "$repo_name" =~ ^_repo- || "$repo_path" =~ \.\./repo- ]]; then
          warn "Hub repos.md still contains placeholder row '$repo_name'"
          errors=$((errors + 1))
          continue
        fi

        if [[ ! "$repo_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
          warn "Hub repo id '$repo_name' must be kebab-case"
          errors=$((errors + 1))
        fi

        if printf '%s\n' "$seen_repo_ids" | grep -Fxq "$repo_name"; then
          warn "Duplicate repo id '$repo_name' in .platform/repos.md"
          errors=$((errors + 1))
        else
          seen_repo_ids="${seen_repo_ids}"$'\n'"$repo_name"
        fi

        resolved_path="$(resolve_repo_path "$repos_file" "$repo_path" 2>/dev/null)" || resolved_path=""
        if [[ -z "$resolved_path" || ! -d "$resolved_path" ]]; then
          warn "Hub repo path '$repo_path' for '$repo_name' does not exist"
          errors=$((errors + 1))
          continue
        fi

        if is_placeholder_value "$repo_ref"; then
          warn "Hub repo '$repo_name' is missing a concrete deep reference file"
          warnings=$((warnings + 1))
        elif [[ ! -f "./.platform/$repo_ref" ]]; then
          warn "Hub repo '$repo_name' deep reference file .platform/$repo_ref does not exist"
          warnings=$((warnings + 1))
        fi

        if [[ -x "$sync_script" ]] && ! grep -Fq "\"$repo_path\"" "$sync_script" && ! grep -Fq "\"$resolved_path\"" "$sync_script"; then
          warn "Hub repo '$repo_name' is not listed in scripts/sync-context.sh REPOS array"
          warnings=$((warnings + 1))
        fi
      done <<< "$repo_rows"
    fi
  fi

  say
  if (( errors > 0 )); then
    printf '%s%sDoctor found issues%s\n' "$C_BOLD" "$C_RED" "$C_RESET"
    printf '  errors: %s%d%s   warnings: %s%d%s\n' \
      "$C_BOLD" "$errors" "$C_RESET" \
      "$C_BOLD" "$warnings" "$C_RESET"
    say
    return 1
  fi

  printf '%s%sDoctor passed%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  printf '  errors: %s0%s   warnings: %s%d%s\n' \
    "$C_BOLD" "$C_RESET" \
    "$C_BOLD" "$warnings" "$C_RESET"
  say
}

cmd_new_domain() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: agentboard new-domain <domain-slug> [repo-id ...] [--repo <repo-id>]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug must be kebab-case."

  local -a repo_ids=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ -n "${2:-}" ]] || die "new-domain requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      *)
        repo_ids+=("$1")
        shift
        ;;
    esac
  done
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  local repo_ids_text repo_id repo_ids_literal
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  local template="./.platform/domains/TEMPLATE.md"
  local target="./.platform/domains/${slug}.md"

  [[ -f "$template" ]] || die "$template not found. Update agentboard templates first."
  [[ ! -e "$target" ]] || die "$target already exists."

  mkdir -p "./.platform/domains"
  cp "$template" "$target"
  replace_template_literals "$target" \
    "<domain-slug>" "$slug" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$target" "repo_ids" "$repo_ids_literal"

  ok "Created domain: .platform/domains/${slug}.md"
}

cmd_new_stream() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: agentboard new-stream <stream-slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local -a domain_slugs=()
  local stream_type="feature"
  local agent_owner="codex"
  local -a repo_ids=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --domain"
        domain_slugs+=("$2")
        shift 2
        ;;
      --type)
        stream_type="${2:-}"
        shift 2
        ;;
      --agent)
        agent_owner="${2:-}"
        shift 2
        ;;
      --repo)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      *)
        die "Unknown flag for new-stream: $1"
        ;;
    esac
  done

  ((${#domain_slugs[@]})) || die "new-stream requires at least one --domain <domain-slug>"
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  local stream_template="./.platform/work/TEMPLATE.md"
  local stream_target="./.platform/work/${slug}.md"
  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"
  local project_name
  project_name="$(basename "$(pwd)")"

  [[ -f "$stream_template" ]] || die "$stream_template not found."
  [[ -f "$active" ]] || die "$active not found."
  [[ ! -e "$stream_target" ]] || die "$stream_target already exists."

  local domain_slugs_text domain_slug domain_file
  domain_slugs_text="$(printf '%s\n' "${domain_slugs[@]}" | unique_nonempty_lines)"
  while IFS= read -r domain_slug; do
    [[ -n "$domain_slug" ]] || continue
    [[ "$domain_slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug '$domain_slug' must be kebab-case."
    domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || die "$domain_file does not exist. Create the domain first."
  done <<< "$domain_slugs_text"

  local repo_ids_text repo_id
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"

  local domain_slugs_literal repo_ids_literal
  domain_slugs_literal="$(frontmatter_inline_array <<< "$domain_slugs_text")"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  cp "$stream_template" "$stream_target"
  replace_template_literals "$stream_target" \
    "<stream-slug>" "$slug" \
    "type: feature" "type: $stream_type" \
    "agent_owner: claude-code" "agent_owner: $agent_owner" \
    "status: planning" "status: planning" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$stream_target" "domain_slugs" "$domain_slugs_literal"
  replace_frontmatter_line "$stream_target" "repo_ids" "$repo_ids_literal"

  local row="| $slug | $stream_type | planning | $agent_owner | $(today) |"
  if grep -qF "| _(none)_ | — | — | — | — |" "$active"; then
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      $0 == "| _(none)_ | — | — | — | — |" { print row; next }
      { print }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  elif grep -qF "| $slug |" "$active"; then
    die "work/ACTIVE.md already has a row for '$slug'"
  else
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      /^---$/ && !inserted { print row; inserted=1 }
      { print }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  fi

  if brief_is_placeholder "$brief"; then
    write_brief_stub "$brief" "$project_name" "$slug" "$domain_slugs_text" "planning"
    ok "Updated work/BRIEF.md with a starter brief"
  else
    warn "work/BRIEF.md already has content. Stream created, but BRIEF.md was left untouched."
  fi

  ok "Created stream: .platform/work/${slug}.md"
  ok "Registered stream in .platform/work/ACTIVE.md"
}

cmd_resolve() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: agentboard resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>"

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

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
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

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
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

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
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
    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "repo"
    printf '  id:   %s\n' "repo-primary"
    printf '  path: %s\n' "."
    printf '  stack: %s\n' "(see .platform/repos.md or activation output)"
    say
    return 0
  fi

  die "Could not resolve '$target' as a stream, domain, or repo id."
}

cmd_handoff() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local requested_slug="${1:-}"
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
      die "No active streams found. Use 'agentboard new-stream ...' or update .platform/work/ACTIVE.md first."
    elif (( count > 1 )); then
      warn "Multiple active streams found:"
      printf '%s\n' "$rows" | awk -F'|' '{ printf "  - %s (%s, %s)\n", $1, $2, $3 }' >&2
      die "Usage: agentboard handoff <stream-slug>"
    else
      IFS='|' read -r slug type status agent updated <<< "$rows"
    fi
  fi

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."

  local next_action
  next_action="$(stream_next_action "$stream_file")"
  [[ -n "$next_action" ]] || next_action="(not set)"

  local build_excerpt current_excerpt do_not_load
  build_excerpt="$(markdown_section_excerpt "$brief" "## What we're building")"
  current_excerpt="$(markdown_section_excerpt "$brief" "## Current state")"
  do_not_load="$(sed -n 's/^\*\*Do not load:\*\* //p' "$brief")"
  do_not_load="${do_not_load%%$'\n'*}"

  printf '\n%s%sagentboard handoff%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  stream: %s%s%s\n' "$C_BOLD" "$slug" "$C_RESET"
  printf '  id:     %s\n' "$(frontmatter_value "$stream_file" "stream_id")"
  printf '  type:   %s\n' "${type:-unknown}"
  printf '  status: %s\n' "${status:-unknown}"
  printf '  owner:  %s\n' "${agent:-unknown}"
  printf '  updated:%s %s\n' "${updated:+ }" "${updated:-unknown}"
  say

  printf '%sLoad in this order:%s\n' "$C_BOLD" "$C_RESET"
  printf '  1. .platform/work/BRIEF.md\n'
  printf '  2. .platform/work/%s.md\n' "$slug"

  local domain_slug
  local domain_index=3
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    printf '  %d. .platform/domains/%s.md\n' "$domain_index" "$domain_slug"
    domain_index=$((domain_index + 1))
  done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
  say

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
}

