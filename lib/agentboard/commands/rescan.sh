cmd_rescan() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local protocol="./.platform/RESCAN.md"
  local log="./.platform/memory/log.md"

  printf '\n%s%sab rescan%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  say

  # Last scan date — look for most recent rescan or activation line in log
  local last_scan=""
  if [[ -f "$log" ]]; then
    last_scan="$(grep -E 'ab rescan|ab activation' "$log" | tail -1 || true)"
  fi
  if [[ -n "$last_scan" ]]; then
    printf '  %sLast scan:%s %s\n' "$C_DIM" "$C_RESET" "$last_scan"
  else
    printf '  %sLast scan:%s %snever (no rescan or activation entry in log.md)%s\n' \
      "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
  fi
  say

  # Content file inventory
  head "Content files"
  local f label staleness
  for f in \
    "./.platform/STATUS.md" \
    "./.platform/architecture.md" \
    "./.platform/memory/decisions.md" \
    "./.platform/memory/log.md"; do
    label="$(printf '%s' "$f" | sed 's|^\./\.platform/||')"
    if [[ -f "$f" ]]; then
      printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$label"
    else
      printf '  %s✗%s %s%s  (missing)%s\n' "$C_YELLOW" "$C_RESET" "$C_DIM" "$label" "$C_RESET"
    fi
  done

  local domain_count conv_count
  domain_count=0
  [[ -d "./.platform/domains" ]] && \
    domain_count="$(find ./.platform/domains -name '*.md' ! -name 'TEMPLATE.md' 2>/dev/null | wc -l | tr -d ' ')"
  conv_count=0
  [[ -d "./.platform/conventions" ]] && \
    conv_count="$(find ./.platform/conventions -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  printf '  %s✓%s domains/       (%s files)\n' "$C_GREEN" "$C_RESET" "$domain_count"
  printf '  %s✓%s conventions/   (%s files)\n' "$C_GREEN" "$C_RESET" "$conv_count"
  say

  # Protocol check
  if [[ ! -f "$protocol" ]]; then
    warn "RESCAN.md not found at $protocol — run 'ab update' to install it."
    say
    return 1
  fi

  bold "Next step"
  printf '  Read %s.platform/RESCAN.md%s and follow the protocol.\n' "$C_CYAN" "$C_RESET"
  printf '  It will guide you through updating STATUS.md, architecture.md,\n'
  printf '  domains/, and conventions/ from the current codebase state.\n'
  say
}
