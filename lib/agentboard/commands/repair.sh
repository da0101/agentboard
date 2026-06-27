# -----------------------------------------------------------------------------
# ab repair - repair safe Agentboard path drift, refresh shipped files, validate.
# -----------------------------------------------------------------------------

_repair_usage() {
  cat <<'EOF'
Usage: ab repair [--dry-run] [--max-passes N]

Scans generated Agentboard context files for known stale paths, rewrites safe
matches, refreshes shipped process files with ab update, then runs doctor and
validate until green or no further safe repair exists.

Flags:
  --dry-run       Report findings without writing files or running update.
  --max-passes N  Maximum repair/validate attempts (default: 2).
EOF
}

_repair_candidates() {
  local f dir
  for f in ./*.md ./*.markdown; do
    [[ -f "$f" ]] && printf '%s\n' "${f#./}"
  done

  for dir in .platform .claude .agents .codex; do
    [[ -d "$dir" ]] || continue
    find "$dir" \
      \( -path ".platform/work/archive" -o \
         -path ".platform/work/archive/*" -o \
         -path ".platform/graphify" -o \
         -path ".platform/graphify/*" \) -prune -o \
      -type f \( \
        -name "*.md" -o -name "*.markdown" -o -name "*.json" -o \
        -name "*.toml" -o -name "*.sh" -o -name "*.js" -o \
        -name "*.yml" -o -name "*.yaml" \
      \) -print 2>/dev/null
  done | sort -u
  return 0
}

_repair_file_has_stale_paths() {
  local file="$1"
  grep -Fq ".claude/roles" "$file" 2>/dev/null
}

_repair_scan_stale_paths() {
  local file
  while IFS= read -r file; do
    [[ -n "$file" && -f "$file" ]] || continue
    _repair_file_has_stale_paths "$file" && printf '%s\n' "$file"
  done < <(_repair_candidates)
  return 0
}

_repair_rewrite_file() {
  local file="$1" tmp
  tmp="$(mktemp)"
  sed \
    -e 's|\.claude/roles/INDEX\.md|.platform/roles/INDEX.md|g' \
    -e 's|\.claude/roles/|.platform/roles/|g' \
    -e 's|\.claude/roles|.platform/roles|g' \
    "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
  return 0
}

_repair_validate_pass() {
  local doctor_out validate_out
  if ! doctor_out="$(cmd_doctor --ci 2>&1)"; then
    printf '%s\n' "$doctor_out"
    return 1
  fi
  printf '%s\n' "$doctor_out"

  if ! validate_out="$(cmd_validate --ci 2>&1)"; then
    printf '%s\n' "$validate_out"
    return 1
  fi
  printf '%s\n' "$validate_out"
  return 0
}

cmd_repair() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local dry_run=0 max_passes=2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --max-passes)
        [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || die "--max-passes expects a positive integer"
        max_passes="$2"
        shift 2
        ;;
      -h|--help) _repair_usage; return 0 ;;
      *) die "Unknown repair flag: $1" ;;
    esac
  done

  printf '\n%s%sab repair%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  (( dry_run )) && warn "Dry-run mode - no files will be changed."

  local pass=1 changed=0 stale_count=0 file stale_files
  while (( pass <= max_passes )); do
    head "Pass ${pass}: scanning known Agentboard path drift"
    stale_files="$(_repair_scan_stale_paths)"
    stale_count=0
    if [[ -n "$stale_files" ]]; then
      while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        stale_count=$((stale_count + 1))
        if (( dry_run )); then
          warn "$file contains stale .claude/roles path(s)"
        elif _repair_rewrite_file "$file"; then
          ok "$file: .claude/roles -> .platform/roles"
          changed=$((changed + 1))
        fi
      done <<< "$stale_files"
    else
      ok "No stale .claude/roles paths found"
    fi

    if (( dry_run )); then
      say
      if (( stale_count > 0 )); then
        printf '%s%sDry-run found %d file(s) to repair.%s\n' "$C_BOLD" "$C_YELLOW" "$stale_count" "$C_RESET"
      else
        printf '%s%sDry-run found no path drift.%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
      fi
      return 0
    fi

    head "Refreshing generated Agentboard files"
    cmd_update

    head "Validating repaired project"
    if _repair_validate_pass; then
      say
      printf '%s%sRepair passed%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
      printf '  changed: %s%d%s file(s)\n' "$C_BOLD" "$changed" "$C_RESET"
      return 0
    fi

    if (( stale_count == 0 )); then
      warn "Validation still fails, and no known safe path repair remains."
      return 1
    fi
    pass=$((pass + 1))
  done

  warn "Repair did not reach green after ${max_passes} pass(es)."
  return 1
}
