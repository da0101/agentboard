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
        # Both present. If dst is an unchanged shipped placeholder (user never
        # wrote to it — e.g. `agentboard update` just created it), overwrite
        # with the real content at src. Otherwise keep both and warn.
        if _migrate_layout_is_shipped_placeholder "$dst" "$name"; then
          if (( dry_run )); then
            printf '  %s+%s %s → %s  %s(overwriting untouched placeholder)%s\n' \
              "$C_CYAN" "$C_RESET" "$src" "$dst" "$C_DIM" "$C_RESET"
          else
            mv -f "$src" "$dst"
            printf '  %s✓%s %s → %s  %s(overwrote untouched placeholder)%s\n' \
              "$C_GREEN" "$C_RESET" "$src" "$dst" "$C_DIM" "$C_RESET"
          fi
          moved=$((moved + 1))
        else
          printf '  %s!%s %s %sand%s %s %sboth have content — kept %s, left %s at root. Resolve manually.%s\n' \
            "$C_YELLOW" "$C_RESET" "$dst" "$C_DIM" "$C_RESET" "$src" \
            "$C_DIM" "$dst" "$src" "$C_RESET"
          skipped=$((skipped + 1))
        fi
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
  local rewrites=0
  _migrate_layout_rewrite_stale_refs "$apply" "$dry_run" rewrites

  printf '\n'
  if (( dry_run )); then
    if (( moved > 0 || rewrites > 0 )); then
      say "${C_BOLD}Plan:${C_RESET} $moved file move(s), $rewrites file(s) with stale refs, $already already migrated, $skipped skipped"
      say "${C_DIM}Run again with --apply to perform the migration.${C_RESET}"
    else
      ok "Nothing to migrate — .platform/ layout is already current."
    fi
  else
    ok "Migration applied: $moved moved, $rewrites file(s) with stale refs rewritten, $already already current, $skipped skipped"
    if (( moved > 0 || rewrites > 0 )); then
      say "${C_DIM}Commit the change with: git add -A && git commit -m 'Migrate .platform/ to memory/ layout'${C_RESET}"
    fi
  fi
}

# Detect whether `dst` is an unchanged shipped placeholder — i.e. `agentboard
# update` or `init` just created it and the user hasn't written anything.
# We compare byte-for-byte against the template shipped in this agentboard
# install. If identical, safe to overwrite with a real root-level file.
_migrate_layout_is_shipped_placeholder() {
  local dst="$1" name="$2"
  local shipped="$TEMPLATES_PLATFORM/memory/$name"
  [[ -f "$shipped" ]] || return 1
  cmp -s "$dst" "$shipped" 2>/dev/null
}

# Rewrite `.platform/<name>.md` → `.platform/memory/<name>.md` in user-owned
# content files. Skips archive/ (historical, read-only). Covers:
#   - conventions/*.md
#   - work/*.md (active streams only, NOT archive)
#   - templates/**/*.md and *.template
#   - agents/*.md
#   - domains/*.md
# Also rewrites top-level *.md except the ones at root that stay put.
_migrate_layout_rewrite_stale_refs() {
  local apply="$1" dry_run="$2" __count_ref="$3"
  head "Stale path references in user content"

  local -a names=(log decisions learnings gotchas playbook open-questions BACKLOG)
  local -a candidates=()
  local d

  for d in conventions work agents domains; do
    [[ -d "./.platform/$d" ]] || continue
    while IFS= read -r f; do
      candidates+=("$f")
    done < <(find "./.platform/$d" -type f \( -name '*.md' -o -name '*.template' \) -not -path '*/archive/*' 2>/dev/null)
  done
  # Include templates/repo/ templates (sibling repo scaffolds)
  if [[ -d "./.platform/templates" ]]; then
    while IFS= read -r f; do
      candidates+=("$f")
    done < <(find "./.platform/templates" -type f \( -name '*.md' -o -name '*.template' \) 2>/dev/null)
  fi
  # Include a couple of root files users commonly edit
  for f in ./.platform/workflow.md ./.platform/architecture.md ./.platform/ONBOARDING.md ./.platform/ACTIVATE.md ./.platform/ACTIVATE-HUB.md; do
    [[ -f "$f" ]] && candidates+=("$f")
  done

  local rewritten=0 file name needs_rewrite pattern
  if (( ${#candidates[@]} == 0 )); then
    printf '  %s·%s no user content files to scan\n' "$C_DIM" "$C_RESET"
    printf -v "$__count_ref" '%d' "0"
    return 0
  fi
  for file in "${candidates[@]}"; do
    needs_rewrite=0
    for name in "${names[@]}"; do
      pattern=".platform/${name}.md"
      if grep -Fq "$pattern" "$file" 2>/dev/null; then
        # Extra guard: don't match ".platform/memory/<name>.md" (already migrated)
        # grep -F matches the literal; accept if any line contains .platform/<name>.md
        # that's NOT preceded by "memory/".
        if grep -E "\.platform/${name}\.md" "$file" 2>/dev/null | grep -v "\.platform/memory/${name}\.md" > /dev/null; then
          needs_rewrite=1
          break
        fi
      fi
    done

    (( needs_rewrite )) || continue

    if (( dry_run )); then
      printf '  %s+%s rewrite refs in %s\n' "$C_CYAN" "$C_RESET" "$file"
    else
      local tmp
      tmp="$(mktemp)"
      # Single awk pass: replace .platform/<name>.md → .platform/memory/<name>.md
      # only when NOT already under memory/.
      awk -v names="log|decisions|learnings|gotchas|playbook|open-questions|BACKLOG" '
        {
          line = $0
          # Replace occurrences of .platform/<name>.md that are NOT already
          # under .platform/memory/. We do two passes: first convert any
          # already-correct .platform/memory/<name>.md to a sentinel, rewrite
          # the bare form, then restore the sentinel.
          while (match(line, "\\.platform/memory/(" names ")\\.md")) {
            pre = substr(line, 1, RSTART - 1)
            hit = substr(line, RSTART, RLENGTH)
            post = substr(line, RSTART + RLENGTH)
            # replace ".platform/memory/" in hit with a sentinel we know wont collide
            gsub(/\.platform\/memory\//, "\x01MEMORY\x01", hit)
            line = pre hit post
          }
          while (match(line, "\\.platform/(" names ")\\.md")) {
            pre = substr(line, 1, RSTART - 1)
            hit = substr(line, RSTART, RLENGTH)
            post = substr(line, RSTART + RLENGTH)
            sub(/\.platform\//, ".platform/memory/", hit)
            line = pre hit post
          }
          gsub(/\x01MEMORY\x01/, ".platform/memory/", line)
          print line
        }
      ' "$file" > "$tmp"
      mv "$tmp" "$file"
      printf '  %s✓%s rewrote refs in %s\n' "$C_GREEN" "$C_RESET" "$file"
    fi
    rewritten=$((rewritten + 1))
  done

  if (( rewritten == 0 )); then
    printf '  %s·%s no stale references found\n' "$C_DIM" "$C_RESET"
  fi
  printf -v "$__count_ref" '%d' "$rewritten"
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
