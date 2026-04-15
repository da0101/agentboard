cmd_init() {
  require_templates

  printf '\n%s%sagentboard init%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%sScaffolds a %s.platform/%s%s context pack + activation prompt.%s\n' \
    "$C_DIM" "$C_RESET$C_CYAN$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

  local target; target="$(pwd)"
  printf '%s  target:%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"

  if [[ -d "$target/.platform" ]]; then
    say
    warn "$target/.platform already exists."
    ask_yes_no "Overwrite it? (contents will be deleted)" || die "aborted."
    rm -rf "$target/.platform"
  fi

  # -------------------------------------------------------------------------
  # Empty-folder / hub detection
  #
  # If the folder looks empty for agentboard purposes (no code, no manifests,
  # no source dirs), ask the user whether this is a "platform brains hub"
  # coordinating sibling repos rather than a single project. If the folder
  # contains only sibling repos (each with its own .git/ or manifest), treat
  # that as a strong hub signal and default the prompt to YES.
  # -------------------------------------------------------------------------
  local hub_mode=0
  local folder_kind
  folder_kind="$(detect_folder_kind "$target")"

  if [[ "$folder_kind" == "hub-candidate" ]]; then
    head "Platform brains hub detected"
    printf '  %sThis folder contains only subdirectories that look like their own repos%s\n' "$C_DIM" "$C_RESET"
    printf '  %s(each has a %s.git/%s%s or its own manifest). That usually means this is a%s\n' "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    printf '  %sparent folder holding %s.platform/%s%s for several sibling repos, not a single project.%s\n' "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    say
    if ask_yes_no_default \
      'Is this a platform brains hub coordinating sibling repos?' \
      'Y' \
      'Answering YES configures .platform/repos.md for multi-repo mode and skips the single-project CLAUDE.md stub. Answering NO falls back to the normal project flow.'; then
      hub_mode=1
    fi
  elif [[ "$folder_kind" == "empty" ]]; then
    head "Empty folder detected"
    printf '  %sThis folder looks empty (no code files, no manifests, no source subdirectories).%s\n' "$C_DIM" "$C_RESET"
    say
    if ask_yes_no_default \
      'Is this going to be a platform brains hub coordinating sibling repos?' \
      'N' \
      'A hub is a parent folder that holds .platform/ for several sibling repos (e.g. backend + frontend + widget), rather than a single codebase. Answer NO if you plan to write code directly in this folder.'; then
      hub_mode=1
    fi
  fi

  head "Project info"
  if (( hub_mode )); then
    printf '  %sI will ask 2 quick questions. Press %sEnter%s%s to accept the default in [brackets].%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  else
    printf '  %sI will ask 2 quick questions. Press %sEnter%s%s to accept the default in [brackets].%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  fi

  local project_name project_desc
  project_name="$(ask \
    'Project name' \
    "$(basename "$target")" \
    'Used in the platform pack headers and log entries. The folder name is usually fine.')"

  if (( hub_mode )); then
    project_desc="$(ask \
      'Short description (1 sentence)' \
      'Platform brains hub — coordinates context for sibling repos' \
      'A brief sentence describing what this hub coordinates — e.g. "Backend + admin + widget for SaaS X", "Mobile app + API + analytics pipeline". The LLM will refine this during activation, so rough is fine. Press Enter to skip.')"
  else
    project_desc="$(ask \
      'Short description (1 sentence)' \
      'TBD — will be filled during activation' \
      'A brief sentence describing the project — e.g. "iOS app for meal planning", "Rust CLI for log parsing", "marketing landing page for SaaS X". The LLM will refine this during activation, so rough is fine. Press Enter to skip.')"
  fi

  head "Scaffolding .platform/"
  mkdir -p "$target/.platform"
  cp -R "$TEMPLATES_PLATFORM/." "$target/.platform/"
  ok "Copied platform skeleton → $C_CYAN$target/.platform/$C_RESET"

  # Hub vs. project: swap in the hub-mode repos.md and ACTIVATE-HUB.md and
  # remove the single-project variants the hub doesn't use. In project mode,
  # strip out the hub-only files so they don't confuse the LLM during
  # activation.
  if (( hub_mode )); then
    if [[ -f "$target/.platform/repos.hub.md" ]]; then
      mv "$target/.platform/repos.hub.md" "$target/.platform/repos.md"
    fi
    # Single-project ACTIVATE.md is not used in hub mode — the hub uses
    # ACTIVATE-HUB.md which scans sibling repo paths instead of this folder.
    rm -f "$target/.platform/ACTIVATE.md"
  else
    rm -f "$target/.platform/repos.hub.md"
    rm -f "$target/.platform/ACTIVATE-HUB.md"
  fi

  # Substitute placeholders in the skeletal files
  for f in \
    "$target/.platform/ACTIVATE.md" \
    "$target/.platform/ACTIVATE-HUB.md" \
    "$target/.platform/STATUS.md" \
    "$target/.platform/log.md" \
    "$target/.platform/decisions.md" \
    "$target/.platform/architecture.md" \
    "$target/.platform/repos.md" \
    "$target/.platform/work/ACTIVE.md" \
    "$target/.platform/work/BRIEF.md"; do
    [[ -f "$f" ]] || continue
    substitute "$f" \
      PROJECT_NAME "$project_name" \
      DESCRIPTION  "$project_desc" \
      TODAY        "$(today)"
  done
  ok "Substituted project name + description into skeleton files"
  if (( hub_mode )); then
    ok "Installed → $C_CYAN$target/.platform/ACTIVATE-HUB.md$C_RESET (the hub-mode activation protocol)"
  else
    ok "Installed → $C_CYAN$target/.platform/ACTIVATE.md$C_RESET (the activation protocol)"
  fi

  # Make sync script executable
  if [[ -f "$target/.platform/scripts/sync-context.sh" ]]; then
    chmod +x "$target/.platform/scripts/sync-context.sh"
  fi

  # Root CLAUDE.md — only written if there's no existing one. Existing files
  # are NEVER touched by init; the LLM handles them during activation (Step 4
  # of .platform/ACTIVATE.md) by prepending its section and preserving the
  # original content underneath.
  head "Root entry files (CLAUDE.md / AGENTS.md / GEMINI.md)"
  printf '  %sagentboard %snever%s%s touches existing root entry files during init.%s\n' \
    "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  printf '  %sIf you already have one, the LLM will prepend its section during activation,%s\n' \
    "$C_DIM" "$C_RESET"
  printf '  %spreserving every line of your original content. No deletions, no backups.%s\n' \
    "$C_DIM" "$C_RESET"
  say

  local existing_any=0
  local f_name existing_list=""
  for f_name in CLAUDE.md AGENTS.md GEMINI.md; do
    if [[ -f "$target/$f_name" ]]; then
      existing_any=1
      existing_list="${existing_list:+$existing_list, }$f_name"
    fi
  done

  if [[ -f "$target/CLAUDE.md" ]]; then
    # Prepend a minimal activation notice so the AI reading CLAUDE.md knows
    # agentboard is installed and what to do. Purely additive — original content
    # is preserved in full below the notice. Skip if notice already present
    # (idempotent re-runs).
    if grep -q "<!-- agentboard installed" "$target/CLAUDE.md" 2>/dev/null; then
      printf '  %s↷%s Activation notice already present in %s%s/CLAUDE.md%s — skipping\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
    else
      local ab_notice
      ab_notice="$(cat <<NOTICE
<!-- agentboard installed $(today) -->
> **agentboard is installed** in \`.platform/\`. When the user says "activate this project" (or "fill in the platform pack", "run agentboard activation"), read \`.platform/ACTIVATE.md\` and follow its 6-step protocol. It covers scanning the project, interviewing the user, filling \`.platform/\`, and prepending a steady-state section to this file (without deleting any existing content).

---

NOTICE
)"
      local original_content
      original_content="$(cat "$target/CLAUDE.md")"
      printf '%s%s' "$ab_notice" "$original_content" > "$target/CLAUDE.md"
      printf '  %s↷%s Prepended activation notice → %s%s/CLAUDE.md%s (original content preserved below)\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
    fi
  else
    # Hub mode uses a specialized "platform brains hub" stub pointing at
    # ACTIVATE-HUB.md. Single-project mode uses the normal stub pointing at
    # ACTIVATE.md.
    local root_template=""
    local root_activate_ref=""
    if (( hub_mode )); then
      if [[ -f "$TEMPLATES_ROOT/CLAUDE.md.hub.template" ]]; then
        root_template="$TEMPLATES_ROOT/CLAUDE.md.hub.template"
        root_activate_ref=".platform/ACTIVATE-HUB.md"
      fi
    else
      if [[ -f "$TEMPLATES_ROOT/CLAUDE.md.template" ]]; then
        root_template="$TEMPLATES_ROOT/CLAUDE.md.template"
        root_activate_ref=".platform/ACTIVATE.md"
      fi
    fi
    if [[ -n "$root_template" ]]; then
      cp "$root_template" "$target/CLAUDE.md"
      substitute "$target/CLAUDE.md" \
        PROJECT_NAME "$project_name" \
        DESCRIPTION  "$project_desc" \
        TODAY        "$(today)"
      if (( hub_mode )); then
        ok "Wrote → $C_CYAN$target/CLAUDE.md$C_RESET (hub stub pointing at $root_activate_ref)"
      else
        ok "Wrote → $C_CYAN$target/CLAUDE.md$C_RESET (short stub pointing at $root_activate_ref)"
      fi
    fi
  fi

  for f_name in AGENTS.md GEMINI.md; do
    if [[ -f "$target/$f_name" ]]; then
      printf '  %s↷%s Kept existing %s%s/%s%s (will be updated during activation)\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$f_name" "$C_RESET"
    else
      local f_template="$TEMPLATES_ROOT/$f_name.template"
      if [[ -f "$f_template" ]]; then
        cp "$f_template" "$target/$f_name"
        substitute "$target/$f_name" \
          PROJECT_NAME "$project_name" \
          DESCRIPTION  "$project_desc" \
          TODAY        "$(today)"
        ok "Wrote → $C_CYAN$target/$f_name$C_RESET (stub — Codex/Gemini entry point)"
      fi
    fi
  done

  # Install project-level Claude Code settings (.claude/settings.json)
  # Contains enforcement hooks: closure gate (blocks premature stream closure) +
  # session bootstrap (structured state report on every session start).
  # Additive-safe: only created if no existing .claude/settings.json is present.
  head "Enforcement hooks (.claude/settings.json)"
  local settings_template="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_target="$target/.claude/settings.json"
  if [[ -f "$settings_target" ]]; then
    printf '  %s↷%s Kept existing %s%s/.claude/settings.json%s (hooks already configured)\n' \
      "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
  elif [[ -f "$settings_template" ]]; then
    mkdir -p "$target/.claude"
    cp "$settings_template" "$settings_target"
    ok "Wrote → $C_CYAN$target/.claude/settings.json$C_RESET (closure gate + session bootstrap hooks)"
  fi
  say

  # Install skills additively — never overwrite existing skills
  # Skills are installed to BOTH .claude/skills/ (Claude Code) and .agents/skills/
  # (Codex CLI + Gemini CLI) so all three providers have the full lifecycle skill set.
  head "Installing skills (.claude/skills/ + .agents/skills/)"
  printf '  %sAdditive install — any pre-existing skill with the same name is left untouched.%s\n' "$C_DIM" "$C_RESET"
  printf '  %sInstalled to both .claude/skills/ (Claude Code) and .agents/skills/ (Codex + Gemini).%s\n' "$C_DIM" "$C_RESET"
  say
  if [[ -d "$TEMPLATES_SKILLS" ]]; then
    local skills_target_claude="$target/.claude/skills"
    local skills_target_agents="$target/.agents/skills"
    mkdir -p "$skills_target_claude" "$skills_target_agents"
    local installed=0 skipped=0 skill_name skill_desc
    for skill_dir in "$TEMPLATES_SKILLS"/*/; do
      skill_name="$(basename "$skill_dir")"
      skill_desc="$(skill_description "$skill_dir/SKILL.md")"
      local installed_here=0
      # Install to .claude/skills/ (Claude Code)
      if [[ -e "$skills_target_claude/$skill_name" ]]; then
        skipped=$((skipped + 1))
        printf '    %s↷%s %s%-16s%s %s%s%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "(claude: exists — kept)" "$C_RESET"
      else
        cp -R "$skill_dir" "$skills_target_claude/$skill_name"
        installed_here=1
      fi
      # Install to .agents/skills/ (Codex + Gemini)
      if [[ -e "$skills_target_agents/$skill_name" ]]; then
        skipped=$((skipped + 1))
        printf '    %s↷%s %s%-16s%s %s%s%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "(agents: exists — kept)" "$C_RESET"
      else
        cp -R "$skill_dir" "$skills_target_agents/$skill_name"
        installed_here=1
      fi
      if (( installed_here )); then
        installed=$((installed + 1))
        printf '    %s+%s %s%-16s%s %s%s%s\n' \
          "$C_GREEN" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "$skill_desc" "$C_RESET"
      fi
    done
    say
    ok "Skills: $C_BOLD$installed installed$C_RESET to both .claude/skills/ and .agents/skills/, $skipped skipped"
  fi

  say
  if (( hub_mode )); then
    printf '%s%s━━━ Platform brains hub initialized ━━━%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  1. Edit %s.platform/repos.md%s and list each sibling repo %s(path, stack, deep-reference file)%s.\n' \
      "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '     %sOr run %sagentboard add-repo <path>%s%s from this hub for each sibling to scaffold its entry files.%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    printf '  2. Open this hub in your AI CLI %s(Claude Code / Codex CLI / Gemini CLI)%s\n' "$C_DIM" "$C_RESET"
    printf '  3. Say: %s%s"activate this project"%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  4. The LLM will read %s.platform/ACTIVATE-HUB.md%s, %sscan each sibling repo%s,\n' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '     %sask 5–8 targeted questions%s, and fill in %s.platform/%s based on what it finds.\n' \
      "$C_BOLD" "$C_RESET" "$C_CYAN" "$C_RESET"
    if [[ $existing_any -eq 1 ]]; then
      printf '  5. Your existing %s%s%s will be %spreserved%s — the LLM prepends its section to the top.\n' \
        "$C_CYAN" "$existing_list" "$C_RESET" "$C_BOLD" "$C_RESET"
    fi
    say
    dim "  This is a hub, not a code repo. The LLM will scan sibling repo paths, not this folder."
    say
  else
    printf '%s%s━━━ Next step: activate ━━━%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  1. Open this project in your AI CLI %s(Claude Code / Codex CLI / Gemini CLI)%s\n' "$C_DIM" "$C_RESET"
    printf '  2. Say: %s%s"activate this project"%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  3. The LLM will read %s.platform/ACTIVATE.md%s, %sscan%s your codebase,\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '     %sask 5–8 targeted questions%s, and fill in %s.platform/%s based on what it finds.\n' "$C_BOLD" "$C_RESET" "$C_CYAN" "$C_RESET"
    if [[ $existing_any -eq 1 ]]; then
      printf '  4. Your existing %s%s%s will be %spreserved%s — the LLM prepends its section to the top.\n' \
        "$C_CYAN" "$existing_list" "$C_RESET" "$C_BOLD" "$C_RESET"
    else
      printf '  4. %sCLAUDE.md%s, %sAGENTS.md%s, and %sGEMINI.md%s are already present with\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
      printf '     mandatory protocols pre-loaded. Activation replaces them with project-specific content.\n'
    fi
    say
    dim "  No stack picking. No assumptions. No deletions. The LLM decides based on your actual code."
    say
  fi
}

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

