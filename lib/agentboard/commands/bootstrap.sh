cmd_bootstrap() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local apply_domains=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply-domains)
        apply_domains=1
        shift
        ;;
      *)
        die "Usage: agentboard bootstrap [--apply-domains]"
        ;;
    esac
  done

  local repos_file="./.platform/repos.md"
  local sync_script="./.platform/scripts/sync-context.sh"
  local brief="./.platform/work/BRIEF.md"
  local active="./.platform/work/ACTIVE.md"
  local root_claude="./CLAUDE.md"
  local project_name
  project_name="$(basename "$(pwd)")"

  local is_hub=0
  if [[ -f "$root_claude" ]] && grep -q "PLATFORM BRAINS HUB" "$root_claude"; then
    is_hub=1
  fi

  printf '\n%s%sagentboard bootstrap%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%sGenerate low-risk starter context from the repo layout. This does not invent feature state.%s\n' \
    "$C_DIM" "$C_RESET"
  say

  [[ -f "$repos_file" ]] || die "$repos_file not found."

  local discovered_rows=""
  if (( is_hub )); then
    discovered_rows="$(discover_child_repos "$(pwd)")"
    if [[ -z "$discovered_rows" ]]; then
      discovered_rows="$(concrete_repo_rows "$repos_file")"
    fi
    [[ -n "$discovered_rows" ]] || die "Could not discover sibling repos. Run bootstrap from a hub folder that contains repo subdirectories, or fill .platform/repos.md first."
  else
    local repo_name repo_id stack ref_file abs_path
    repo_name="$(basename "$(pwd)")"
    repo_id="repo-primary"
    stack="$(guess_repo_stack "." "$repo_id")"
    ref_file="$(slugify "$repo_name").md"
    abs_path="$(pwd)"
    discovered_rows="$(printf '%s|%s|%s|%s|%s|%s\n' "$repo_id" "." "$stack" "$ref_file" "$abs_path" "$repo_name")"
  fi

  local repos_table_rows="| Repo ID | Path | Stack | Deep reference |"$'\n'"|---|---|---|---|"$'\n'
  local sync_paths="" repo_id repo_path repo_stack repo_ref repo_abs repo_name
  while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
    [[ -n "$repo_id" ]] || continue
    repos_table_rows="${repos_table_rows}| ${repo_id} | \`${repo_path}\` | ${repo_stack} | \`${repo_ref}\` |"$'\n'
    if (( is_hub )) && [[ -n "$repo_abs" ]]; then
      sync_paths="${sync_paths}${repo_abs}"$'\n'
    fi

    local ref_target="./.platform/${repo_ref}"
    if [[ ! -f "$ref_target" ]]; then
      local repo_fs_path manifest source_dir commands relationships role hint entrypoints boundaries artifacts
      repo_fs_path="."
      [[ "$repo_path" != "." && -n "$repo_abs" ]] && repo_fs_path="$repo_abs"
      role="$(detect_repo_role "$repo_fs_path" "$repo_id")"
      hint="$(detect_repo_stack_hint "$repo_fs_path" "$repo_id" "$role")"
      manifest="$(repo_manifest_file "$repo_fs_path" 2>/dev/null || true)"
      source_dir="$(repo_primary_source_dir "$repo_fs_path")"
      commands="$(repo_bootstrap_commands "$repo_fs_path" "$role" "$hint")"
      relationships="$(repo_relationship_lines "$repo_id" "$repo_fs_path" "$discovered_rows")"
      entrypoints="$(repo_entrypoint_lines "$repo_fs_path")"
      boundaries="$(repo_boundary_lines "$repo_fs_path" "$source_dir")"
      artifacts="$(repo_context_artifact_lines "$repo_fs_path")"
      write_bootstrap_reference "$ref_target" "$repo_id" "$repo_name" "${repo_abs:-$(pwd)}" "$role" "$hint" "$manifest" "$source_dir" "$commands" "$relationships" "$entrypoints" "$boundaries" "$artifacts"
      ok "Created deep reference stub: .platform/${repo_ref}"
    fi
  done <<< "$discovered_rows"

  replace_repos_table "$repos_file" "$repos_table_rows"
  ok "Updated .platform/repos.md from detected repo layout"

  if (( is_hub )) && [[ -f "$sync_script" ]]; then
    write_sync_repos_array "$sync_script" "$sync_paths"
    chmod +x "$sync_script"
    ok "Updated .platform/scripts/sync-context.sh repo list"
  fi

  local inferred_domain_rows existing_domain_rows combined_domain_rows
  inferred_domain_rows="$(infer_bootstrap_domains "$discovered_rows" | merge_bootstrap_domain_rows)"
  existing_domain_rows="$(domain_repo_rows "$repos_file" | merge_bootstrap_domain_rows)"
  combined_domain_rows="$(printf '%s\n%s\n' "$existing_domain_rows" "$inferred_domain_rows" | merge_bootstrap_domain_rows)"

  if [[ -n "$inferred_domain_rows" ]]; then
    head "Inferred domains"
    local domain_slug repo_ids_text repo_id domain_created=0
    while IFS='|' read -r domain_slug repo_id; do
      [[ -n "$domain_slug" && -n "$repo_id" ]] || continue
      repo_ids_text="$(printf '%s\n' "$inferred_domain_rows" | awk -F'|' -v slug="$domain_slug" '$1 == slug { print $2 }' | unique_nonempty_lines)"
      if [[ -f "./.platform/domains/${domain_slug}.md" ]]; then
        printf '  %s↷%s %s%s%s  %s(existing)%s\n' "$C_YELLOW" "$C_RESET" "$C_CYAN" "$domain_slug" "$C_RESET" "$C_DIM" "$C_RESET"
      else
        if (( apply_domains )); then
          create_domain_stub "$domain_slug" "$repo_ids_text"
          ok "Created inferred domain: .platform/domains/${domain_slug}.md"
          domain_created=$((domain_created + 1))
        else
          printf '  %s~%s %s%s%s -> repos %s[%s]%s\n' \
            "$C_YELLOW" "$C_RESET" "$C_CYAN" "$domain_slug" "$C_RESET" \
            "$C_BOLD" "$(printf '%s\n' "$repo_ids_text" | join_lines_comma)" "$C_RESET"
        fi
      fi
    done < <(printf '%s\n' "$inferred_domain_rows" | awk -F'|' '!seen[$1]++ { print $1 "|" $2 }')
    if (( !apply_domains )); then
      printf '  %sRun %sagentboard bootstrap --apply-domains%s to scaffold the missing inferred domain stubs.%s\n' \
        "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_RESET"
    elif (( domain_created == 0 )); then
      printf '  %sNo new inferred domains needed to be created.%s\n' "$C_DIM" "$C_RESET"
    fi
    say
  fi

  local stream_suggestions
  stream_suggestions="$(infer_bootstrap_stream_suggestions "$discovered_rows" "$combined_domain_rows")"
  if [[ -n "$stream_suggestions" ]]; then
    head "Suggested streams"
    local branch stream_slug stream_type domain_slugs_csv domain_flags domain_name confidence
    while IFS='|' read -r repo_id branch stream_slug stream_type domain_slugs_csv confidence; do
      [[ -n "$stream_slug" ]] || continue
      domain_flags=""
      while IFS= read -r domain_name; do
        [[ -n "$domain_name" ]] || continue
        domain_flags="${domain_flags} --domain ${domain_name}"
      done < <(printf '%s\n' "$domain_slugs_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      printf '  %s%s%s  %s(branch: %s, confidence: %s)%s\n' "$C_CYAN" "$stream_slug" "$C_RESET" "$C_DIM" "$branch" "$confidence" "$C_RESET"
      printf '     type: %s\n' "$stream_type"
      printf '     repos: [%s]\n' "$repo_id"
      printf '     domains: [%s]\n' "$domain_slugs_csv"
      printf '     next: %sagentboard new-stream %s%s --type %s --repo %s%s\n' \
        "$C_BOLD" "$stream_slug" "$domain_flags" "$stream_type" "$repo_id" "$C_RESET"
    done <<< "$stream_suggestions"
    say
  fi

  if [[ -f "$brief" && -f "$active" ]] && brief_is_placeholder "$brief"; then
    local rows count selected_slug selected_status selected_stream_file selected_domain_slugs
    rows="$(stream_rows_from_active "$active")"
    count=0
    [[ -n "$rows" ]] && count="$(printf '%s\n' "$rows" | awk 'NF { c++ } END { print c + 0 }')"
    if (( count == 1 )); then
      IFS='|' read -r selected_slug _ selected_status _ _ <<< "$rows"
      selected_stream_file="./.platform/work/${selected_slug}.md"
      if [[ -f "$selected_stream_file" ]]; then
        selected_domain_slugs="$(inline_array_items "$(frontmatter_value "$selected_stream_file" "domain_slugs")")"
        write_brief_stub "$brief" "$project_name" "$selected_slug" "$selected_domain_slugs" "${selected_status:-planning}"
        ok "Seeded work/BRIEF.md from the only active stream"
      fi
    else
      warn "work/BRIEF.md left as placeholder (bootstrap only seeds it when exactly one active stream exists)"
    fi
  fi

  say
  bold "Bootstrap complete"
  if (( is_hub )); then
    printf '  1. Review %s.platform/repos.md%s and the new repo reference stubs.\n' "$C_CYAN" "$C_RESET"
    printf '  2. Review inferred domains/streams above and apply what is real.\n'
    printf '  3. Run %sagentboard doctor%s to verify the shared state.\n' "$C_BOLD" "$C_RESET"
  else
    printf '  1. Review %s.platform/repos.md%s and %s.platform/*.md%s.\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '  2. Review inferred domains/streams above and apply what is real.\n'
    printf '  3. Run %sagentboard doctor%s, then create real domains/streams as needed.\n' "$C_BOLD" "$C_RESET"
  fi
  say
}

