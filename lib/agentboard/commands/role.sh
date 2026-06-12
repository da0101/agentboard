# -----------------------------------------------------------------------------
# ab role — list and inspect agent role profiles (.platform/roles/*.md).
#
# Role files carry YAML frontmatter (slug / name / label / ansi_color /
# mission) plus a full role definition an agent adopts on activation.
# `list` renders a colored table from the frontmatter; `show <slug>` prints
# one role file in full so an agent or user can load it. Pure bash 3.2 +
# the shared frontmatter parser — no deps.
# -----------------------------------------------------------------------------

role_usage() {
  cat <<'EOF'
Usage: ab role [list]        list available role profiles
       ab role show <slug>   print a role profile in full
       ab role --help        show this help

Role profiles live in .platform/roles/*.md. Each file carries YAML
frontmatter (slug, name, label, ansi_color, mission) and a role definition
an agent adopts on activation. See .platform/roles/INDEX.md for the
routing rules. Missing the pack? Run 'ab update' to install it.
EOF
}

# role_frontmatter <file> <key> — frontmatter value with surrounding quotes stripped
role_frontmatter() {
  local value
  value="$(frontmatter_value "$1" "$2")"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

# role_files — one role file path per line, skipping INDEX.md
role_files() {
  local f
  for f in ./.platform/roles/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "INDEX.md" ]] && continue
    printf '%s\n' "$f"
  done
  return 0
}

role_slugs_csv() {
  role_files | sed 's|.*/||; s|\.md$||' | join_lines_comma
}

cmd_role_list() {
  if [[ ! -d "./.platform/roles" ]]; then
    say "No role pack found at .platform/roles/ — run 'ab update' to install the role pack."
    return 0
  fi

  local f label name mission color found=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if (( !found )); then
      printf '  %s%-28s %-26s %s%s\n' "$C_DIM" "LABEL" "NAME" "MISSION" "$C_RESET"
      found=1
    fi
    label="$(role_frontmatter "$f" "label")"
    name="$(role_frontmatter "$f" "name")"
    mission="$(role_frontmatter "$f" "mission")"
    color="$(role_frontmatter "$f" "ansi_color")"
    [[ -n "$label" ]] || label="[role:$(basename "$f" .md)]"
    if [[ -n "$C_RESET" && "$color" =~ ^[0-9]+$ ]]; then
      printf '  \033[38;5;%sm%-28s %-26s %s\033[0m\n' "$color" "$label" "$name" "$mission"
    else
      printf '  %-28s %-26s %s\n' "$label" "$name" "$mission"
    fi
  done < <(role_files)

  if (( !found )); then
    say "No role files in .platform/roles/ — run 'ab update' to install the role pack."
  fi
  return 0
}

cmd_role_show() {
  local slug="${1:-}"
  [[ -n "$slug" ]] || die "Usage: ab role show <slug>"
  [[ -d "./.platform/roles" ]] || \
    die "No role pack found at .platform/roles/ — run 'ab update' to install the role pack."

  local file="./.platform/roles/${slug}.md"
  if [[ "$slug" == "INDEX" || ! -f "$file" ]]; then
    local available
    available="$(role_slugs_csv)"
    [[ -n "$available" ]] || available="(none installed)"
    die "Unknown role: '$slug'. Available roles: $available"
  fi
  cat "$file"
}

cmd_role() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list)           cmd_role_list "$@" ;;
    show)           cmd_role_show "$@" ;;
    help|-h|--help) role_usage ;;
    *)              die "Unknown role subcommand: $sub. Run 'ab role --help'." ;;
  esac
}
