cmd_doctor() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local errors=0 warnings=0 ci_mode=0 _dr_pass=0 _dr_fail=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ci) ci_mode=1; shift ;;
      *) shift ;;
    esac
  done

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

  (( ci_mode == 0 )) && printf '\n%s%sab doctor%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" || true

  if [[ -f "$brief" ]]; then
    _dr_ok "work/BRIEF.md present"
  else
    _dr_warn "Missing .platform/work/BRIEF.md"
    errors=$((errors + 1))
  fi

  if [[ -f "$active" ]]; then
    _dr_ok "work/ACTIVE.md present"
  else
    _dr_warn "Missing .platform/work/ACTIVE.md"
    errors=$((errors + 1))
  fi

  if [[ -d "$domains_dir" ]]; then
    _dr_ok "domains/ directory present"
  else
    _dr_warn "Missing .platform/domains/"
    errors=$((errors + 1))
  fi

  local _not_yet_activated=0
  if [[ -f "$root_claude" ]] && grep -q "NOT YET ACTIVATED" "$root_claude"; then
    _dr_ok "Activation stub detected — sync check skipped until activation"
    _not_yet_activated=1
  elif (( ci_mode )); then
    _dr_ci_check_sync "$sync_script"
  elif [[ -x "$sync_script" ]]; then
    local sync_output=""
    if sync_output="$("$sync_script" 2>&1)"; then
      _dr_ok "Root entry files in sync"
    else
      _dr_warn "Entry file drift detected by sync-context.sh"
      printf '%s\n' "$sync_output" >&2
      warnings=$((warnings + 1))
    fi
  else
    _dr_warn "sync-context.sh missing or not executable"
    warnings=$((warnings + 1))
  fi

  # Activation quality: only meaningful after activation has run
  if (( _not_yet_activated == 0 )); then
    local arch_file="./.platform/architecture.md"
    local conv_dir="./.platform/conventions"
    if [[ -f "$arch_file" ]] && grep -q '{{' "$arch_file" 2>/dev/null; then
      _dr_warn "architecture.md still has unfilled {{PLACEHOLDER}} content — run activation ('activate this project')"
      warnings=$((warnings + 1))
    fi
    if [[ -d "$conv_dir" ]] && [[ -z "$(ls -A "$conv_dir" 2>/dev/null)" ]]; then
      _dr_warn "conventions/ is empty — activation should write at least one stack conventions file"
      warnings=$((warnings + 1))
    fi
  fi

  local seen_stream_ids="" seen_domain_ids=""
  local stream_file stream_slug stream_id
  while IFS= read -r stream_file; do
    [[ -n "$stream_file" ]] || continue
    stream_slug="$(basename "$stream_file" .md)"

    if is_legacy_stream_file "$stream_file"; then
      _dr_warn "Stream '$stream_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    stream_id="$(frontmatter_value "$stream_file" "stream_id")"

    if is_placeholder_value "$stream_id"; then
      _dr_warn "Stream '$stream_slug' is missing frontmatter key 'stream_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$stream_id" != "$(canonical_stream_id "$stream_slug")" ]]; then
      _dr_warn "Stream '$stream_slug' has non-canonical stream_id '$stream_id' (expected '$(canonical_stream_id "$stream_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_stream_ids" | grep -Fxq "$stream_id"; then
      _dr_warn "Duplicate stream_id '$stream_id' detected"
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
      _dr_warn "Domain '$domain_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    domain_id="$(frontmatter_value "$domain_file" "domain_id")"

    if is_placeholder_value "$domain_id"; then
      _dr_warn "Domain '$domain_slug' is missing frontmatter key 'domain_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$domain_id" != "$(canonical_domain_id "$domain_slug")" ]]; then
      _dr_warn "Domain '$domain_slug' has non-canonical domain_id '$domain_id' (expected '$(canonical_domain_id "$domain_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_domain_ids" | grep -Fxq "$domain_id"; then
      _dr_warn "Duplicate domain_id '$domain_id' detected"
      errors=$((errors + 1))
    else
      seen_domain_ids="${seen_domain_ids}"$'\n'"$domain_id"
    fi
  done < <(domain_files)

  if [[ -f "$active" ]]; then
    local stream_rows=""
    stream_rows="$(stream_rows_from_active "$active" | awk -F'|' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')"

    if [[ -z "$stream_rows" ]]; then
      _dr_ok "No active streams registered"
    else
      local slug row_type row_status row_agent stream_file value
      while IFS='|' read -r slug row_type row_status row_agent; do
        [[ -z "$slug" ]] && continue
        stream_file="./.platform/work/${slug}.md"

        if [[ ! -f "$stream_file" ]]; then
          _dr_warn "Active stream '$slug' is missing file .platform/work/${slug}.md"
          errors=$((errors + 1))
          continue
        fi

        _dr_ok "Found stream file for '$slug'"

        if is_legacy_stream_file "$stream_file"; then
          local legacy_type legacy_status legacy_agent
          legacy_type="$(legacy_stream_value "$stream_file" "Type")"
          legacy_status="$(legacy_stream_value "$stream_file" "Status")"
          legacy_agent="$(legacy_stream_value "$stream_file" "Agent")"

          [[ -n "$legacy_type" && "$legacy_type" != "$row_type" ]] && {
            _dr_warn "Legacy stream '$slug' type mismatch: ACTIVE.md='$row_type' stream='$legacy_type'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_status" && "$legacy_status" != "$row_status" ]] && {
            _dr_warn "Legacy stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$legacy_status'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_agent" && "$legacy_agent" != "$row_agent" ]] && {
            _dr_warn "Legacy stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$legacy_agent'"
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
                _dr_warn "Stream '$slug' is missing non-empty frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
            closure_approved)
              if [[ "$value" != "true" && "$value" != "false" ]]; then
                _dr_warn "Stream '$slug' has invalid closure_approved value '$value'"
                errors=$((errors + 1))
              fi
              ;;
            *)
              if is_placeholder_value "$value"; then
                _dr_warn "Stream '$slug' is missing frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
          esac
        done

        value="$(frontmatter_value "$stream_file" "slug")"
        if [[ -n "$value" && "$value" != "$slug" ]]; then
          _dr_warn "Stream '$slug' has slug '$value' in frontmatter"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "status")"
        if [[ -n "$value" && "$value" != "$row_status" ]]; then
          _dr_warn "Stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$value'"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "agent_owner")"
        if [[ -n "$row_agent" && "$row_agent" != "—" && -n "$value" && "$value" != "$row_agent" ]]; then
          _dr_warn "Stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$value'"
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
            _dr_warn "Stream '$slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
            errors=$((errors + 1))
          fi
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")

        local domain_slug domain_file domain_value
        while IFS= read -r domain_slug; do
          [[ -z "$domain_slug" ]] && continue
          domain_file="./.platform/domains/${domain_slug}.md"
          if [[ ! -f "$domain_file" ]]; then
            _dr_warn "Stream '$slug' references missing domain file .platform/domains/${domain_slug}.md"
            errors=$((errors + 1))
            continue
          fi

          local domain_keys=(domain_id slug status repo_ids created_at updated_at)
          for key in "${domain_keys[@]}"; do
            domain_value="$(frontmatter_value "$domain_file" "$key")"
            case "$key" in
              repo_ids)
                if [[ -z "$(inline_array_items "$domain_value")" ]]; then
                  _dr_warn "Domain '$domain_slug' is missing non-empty frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
              *)
                if is_placeholder_value "$domain_value"; then
                  _dr_warn "Domain '$domain_slug' is missing frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
            esac
          done

          domain_value="$(frontmatter_value "$domain_file" "slug")"
          if [[ -n "$domain_value" && "$domain_value" != "$domain_slug" ]]; then
            _dr_warn "Domain '$domain_slug' has slug '$domain_value' in frontmatter"
            errors=$((errors + 1))
          fi

          while IFS= read -r repo_id; do
            [[ -z "$repo_id" ]] && continue
            repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
            if [[ -n "$repo_row" ]]; then
              continue
            fi
            if (( is_hub )) || [[ "$repo_id" != "repo-primary" ]]; then
              _dr_warn "Domain '$domain_slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
              errors=$((errors + 1))
            fi
          done < <(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
      done <<< "$stream_rows"
    fi
  fi

  if [[ -f "$brief" ]] && ! brief_is_placeholder "$brief"; then
    if is_legacy_brief_file "$brief"; then
      _dr_warn "work/BRIEF.md uses the legacy multi-stream format. Keep using it for now, or run 'ab brief-upgrade <stream-slug> --apply' when you settle on one active feature brief."
      warnings=$((warnings + 1))
    else
    local brief_stream=""
    brief_stream="$(sed -n 's/^\*\*Stream file:\*\* `work\/\([^`]*\)\.md`$/\1/p' "$brief")"
    brief_stream="${brief_stream%%$'\n'*}"
    if [[ -z "$brief_stream" ]]; then
      _dr_warn "work/BRIEF.md is missing a valid Stream file reference"
      warnings=$((warnings + 1))
    elif [[ ! -f "./.platform/work/${brief_stream}.md" ]]; then
      _dr_warn "work/BRIEF.md references missing stream file .platform/work/${brief_stream}.md"
      errors=$((errors + 1))
    fi

    local brief_domain_count=0
    local brief_domain
    while IFS= read -r brief_domain; do
      [[ -z "$brief_domain" ]] && continue
      brief_domain_count=$((brief_domain_count + 1))
      if [[ ! -f "./.platform/domains/${brief_domain}.md" ]]; then
        _dr_warn "work/BRIEF.md references missing domain file .platform/domains/${brief_domain}.md"
        errors=$((errors + 1))
      fi
    done < <(sed -n 's/^- `\.platform\/domains\/\([^` ]*\)\.md`.*$/\1/p' "$brief")

    if (( brief_domain_count == 0 )); then
      _dr_warn "work/BRIEF.md has no concrete domain references"
      warnings=$((warnings + 1))
    fi
    fi
  fi

  if (( is_hub )) && [[ -f "$repos_file" ]]; then
    if [[ -z "$repo_rows" ]]; then
      _dr_warn "Hub mode detected but .platform/repos.md has no repo rows"
      errors=$((errors + 1))
    else
      local seen_repo_ids=""
      local repo_name repo_path repo_stack repo_ref resolved_path
      while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
        [[ -z "$repo_name" ]] && continue

        if [[ "$repo_name" =~ ^_repo- || "$repo_path" =~ \.\./repo- ]]; then
          _dr_warn "Hub repos.md still contains placeholder row '$repo_name'"
          errors=$((errors + 1))
          continue
        fi

        if [[ ! "$repo_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
          _dr_warn "Hub repo id '$repo_name' must be kebab-case"
          errors=$((errors + 1))
        fi

        if printf '%s\n' "$seen_repo_ids" | grep -Fxq "$repo_name"; then
          _dr_warn "Duplicate repo id '$repo_name' in .platform/repos.md"
          errors=$((errors + 1))
        else
          seen_repo_ids="${seen_repo_ids}"$'\n'"$repo_name"
        fi

        resolved_path="$(resolve_repo_path "$repos_file" "$repo_path" 2>/dev/null)" || resolved_path=""
        if [[ -z "$resolved_path" || ! -d "$resolved_path" ]]; then
          _dr_warn "Hub repo path '$repo_path' for '$repo_name' does not exist"
          errors=$((errors + 1))
          continue
        fi

        if is_placeholder_value "$repo_ref"; then
          _dr_warn "Hub repo '$repo_name' is missing a concrete deep reference file"
          warnings=$((warnings + 1))
        elif [[ ! -f "./.platform/$repo_ref" ]]; then
          _dr_warn "Hub repo '$repo_name' deep reference file .platform/$repo_ref does not exist"
          warnings=$((warnings + 1))
        fi

        if [[ -x "$sync_script" ]] && ! grep -Fq "\"$repo_path\"" "$sync_script" && ! grep -Fq "\"$resolved_path\"" "$sync_script"; then
          _dr_warn "Hub repo '$repo_name' is not listed in scripts/sync-context.sh REPOS array"
          warnings=$((warnings + 1))
        fi
      done <<< "$repo_rows"
    fi
  fi

  (( ci_mode == 0 )) && _dr_check_git_hooks
  (( ci_mode == 0 )) && _dr_check_provider_wrappers

  if agentboard_runtime_gitignore_is_current "./.gitignore"; then
    _dr_ok "Runtime artifacts ignored in .gitignore"
  else
    _dr_warn ".gitignore is missing the ab runtime block (.platform/events.jsonl, .daemon-port, .file-locks.json, watcher/session state). Run 'ab update' to install it."
    warnings=$((warnings + 1))
  fi

  (( ci_mode )) && { _dr_ci_summary; return; } || true

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
