cmd_migrate_layout() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local apply=0 dry_run=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; dry_run=0; shift ;;
      --dry-run) dry_run=1; apply=0; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: agentboard migrate-layout [--apply|--dry-run]

Upgrades an existing .platform/ directory to the current layout (memory/
folder for accumulated knowledge). Safe to re-run: only moves files that
are still at their old location, leaves already-migrated files alone.

Default:  --dry-run (print what would change)
  --apply  Actually move files and clean up

Phase 1 migration:
  .platform/decisions.md      → .platform/memory/decisions.md
  .platform/learnings.md      → .platform/memory/learnings.md
  .platform/log.md            → .platform/memory/log.md
  .platform/gotchas.md        → .platform/memory/gotchas.md
  .platform/playbook.md       → .platform/memory/playbook.md
  .platform/open-questions.md → .platform/memory/open-questions.md
  .platform/BACKLOG.md        → .platform/memory/BACKLOG.md

Also cleans up legacy sessions/ folder if empty (superseded by streams).
EOF
        return 0 ;;
      *) die "Unknown flag for migrate-layout: $1" ;;
    esac
  done

  if (( dry_run )); then
    say "${C_BOLD}Dry run — no files will be moved. Use --apply to migrate.${C_RESET}"
    printf '\n'
  fi

  local moved=0 skipped=0 already=0
  local -a memory_files=(
    "decisions.md"
    "learnings.md"
    "log.md"
    "gotchas.md"
    "playbook.md"
    "open-questions.md"
    "BACKLOG.md"
  )

  head "Memory files → .platform/memory/"

  if (( apply )); then
    mkdir -p "./.platform/memory"
  fi

  local name src dst
  for name in "${memory_files[@]}"; do
    src="./.platform/${name}"
    dst="./.platform/memory/${name}"

    if [[ -f "$dst" ]]; then
      if [[ -f "$src" ]]; then
        printf '  %s!%s %s %sand%s %s %sboth present — kept %s, leaving old at %s%s\n' \
          "$C_YELLOW" "$C_RESET" "$dst" "$C_DIM" "$C_RESET" "$src" \
          "$C_DIM" "$dst" "$src" "$C_RESET"
        skipped=$((skipped + 1))
      else
        printf '  %s✓%s %s  %s(already migrated)%s\n' \
          "$C_GREEN" "$C_RESET" "$dst" "$C_DIM" "$C_RESET"
        already=$((already + 1))
      fi
      continue
    fi

    if [[ ! -f "$src" ]]; then
      printf '  %s·%s %s  %s(not present — skipping)%s\n' \
        "$C_DIM" "$C_RESET" "$name" "$C_DIM" "$C_RESET"
      skipped=$((skipped + 1))
      continue
    fi

    if (( dry_run )); then
      printf '  %s+%s %s → %s\n' "$C_CYAN" "$C_RESET" "$src" "$dst"
    else
      mv "$src" "$dst"
      printf '  %s✓%s %s → %s\n' "$C_GREEN" "$C_RESET" "$src" "$dst"
    fi
    moved=$((moved + 1))
  done

  _migrate_layout_cleanup_sessions "$apply" "$dry_run"

  printf '\n'
  if (( dry_run )); then
    if (( moved > 0 )); then
      say "${C_BOLD}Plan:${C_RESET} $moved file(s) to move, $already already migrated, $skipped skipped"
      say "${C_DIM}Run again with --apply to perform the migration.${C_RESET}"
    else
      ok "Nothing to migrate — .platform/ layout is already current."
    fi
  else
    ok "Migration applied: $moved moved, $already already current, $skipped skipped"
    if (( moved > 0 )); then
      say "${C_DIM}Commit the change with: git add -A && git commit -m 'Migrate .platform/ to memory/ layout'${C_RESET}"
    fi
  fi
}

# Remove legacy `.platform/sessions/` folder if empty (superseded by work/ streams)
_migrate_layout_cleanup_sessions() {
  local apply="$1" dry_run="$2"
  local dir="./.platform/sessions"
  [[ -d "$dir" ]] || return 0

  head "Legacy sessions/ folder"
  local file_count
  file_count="$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ -z "$file_count" ]] && file_count=0

  if (( file_count == 0 )); then
    if (( dry_run )); then
      printf '  %s+%s remove empty %s\n' "$C_CYAN" "$C_RESET" "$dir"
    else
      rmdir "$dir" 2>/dev/null || true
      printf '  %s✓%s removed empty %s\n' "$C_GREEN" "$C_RESET" "$dir"
    fi
  else
    printf '  %s!%s %s has %d file(s) — not touching. Review and delete manually if unused.%s\n' \
      "$C_YELLOW" "$C_RESET" "$dir" "$file_count" ""
  fi
}
