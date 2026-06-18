cmd_sync_skills() {
  # Source of truth: templates/skills/ inside the agentboard install.
  # Falls back to .claude/skills/ in the current project if the install
  # source is not accessible (e.g. running from an archived copy).
  local skills_src=""
  if [[ -d "$AGENTBOARD_ROOT/templates/skills" ]]; then
    skills_src="$AGENTBOARD_ROOT/templates/skills"
  elif [[ -d ".claude/skills" ]]; then
    skills_src=".claude/skills"
  else
    die "Cannot locate a skill pack. Expected $AGENTBOARD_ROOT/templates/skills or .claude/skills/ in the current directory."
  fi

  # Collect skill names (each subdirectory in the source tree).
  local -a skill_names=()
  local entry
  for entry in "$skills_src"/*/; do
    [[ -d "$entry" ]] || continue
    skill_names+=("$(basename "$entry")")
  done

  if [[ ${#skill_names[@]} -eq 0 ]]; then
    die "No skills found in $skills_src"
  fi

  local n_skills=${#skill_names[@]}

  # Detect which harness directories exist under the current project root.
  local -a harness_dirs=()
  [[ -d ".claude/skills"  ]] && harness_dirs+=(".claude/skills")
  [[ -d ".agents/skills"  ]] && harness_dirs+=(".agents/skills")
  [[ -d ".cursor/rules"   ]] && harness_dirs+=(".cursor/rules")
  [[ -d ".kiro/steering"  ]] && harness_dirs+=(".kiro/steering")
  [[ -d ".zed"            ]] && { say "  ${C_DIM}.zed/ detected — no per-skill directory convention; skipping.${C_RESET}"; }
  [[ -d ".opencode"       ]] && { say "  ${C_DIM}.opencode/ detected — no per-skill directory convention; skipping.${C_RESET}"; }

  if [[ ${#harness_dirs[@]} -eq 0 ]]; then
    die "No supported harness directories found (.claude/skills, .agents/skills, .cursor/rules, .kiro/steering). Nothing to sync."
  fi

  local n_harnesses=${#harness_dirs[@]}
  local skill name src_skill_dir dest_dir

  for dest_dir in "${harness_dirs[@]}"; do
    say "  Syncing to ${C_BOLD}${dest_dir}${C_RESET} …"

    for name in "${skill_names[@]}"; do
      src_skill_dir="$skills_src/$name"

      case "$dest_dir" in
        .claude/skills|.agents/skills)
          # Direct copy: dest/<name>/SKILL.md
          local dest_skill_dir="$dest_dir/$name"
          mkdir -p "$dest_skill_dir"
          if [[ -f "$src_skill_dir/SKILL.md" ]]; then
            cp "$src_skill_dir/SKILL.md" "$dest_skill_dir/SKILL.md"
          fi
          ;;

        .cursor/rules)
          # Condensed .mdc reference per skill.
          local mdc_file="$dest_dir/${name}.mdc"
          {
            printf -- "---\ndescription: %s skill (agentboard)\nalwaysApply: false\n---\n\n" "$name"
            if [[ -f "$src_skill_dir/SKILL.md" ]]; then
              head -20 "$src_skill_dir/SKILL.md"
            fi
          } > "$mdc_file"
          ;;

        .kiro/steering)
          # Brief steering note per skill.
          local steering_file="$dest_dir/${name}.md"
          {
            printf -- "# %s\n\nSource: agentboard skill pack\n\n" "$name"
            if [[ -f "$src_skill_dir/SKILL.md" ]]; then
              head -10 "$src_skill_dir/SKILL.md"
            fi
          } > "$steering_file"
          ;;
      esac
    done

    ok "  ${dest_dir} — ${n_skills} skill(s) synced"
  done

  ok "Synced ${n_skills} skill(s) to ${n_harnesses} harness(es)."
}
