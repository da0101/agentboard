cmd_search() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local _context=3 _quiet=0 _scope="all"
  local -a _query_words=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)      _search_help; return 0 ;;
      -C|--context)   _context="${2:?'--context requires a number'}"; shift 2 ;;
      -q|--quiet)     _quiet=1; shift ;;
      --domains)      _scope="domains"; shift ;;
      --memory)       _scope="memory"; shift ;;
      --conventions)  _scope="conventions"; shift ;;
      --*)            die "Unknown flag: $1. Run 'ab search --help'." ;;
      *)              _query_words+=("$1"); shift ;;
    esac
  done

  (( ${#_query_words[@]} > 0 )) || die "Usage: ab search <query terms>"

  # OR-join all query words into a single regex pattern
  local _pattern
  _pattern="$(IFS='|'; printf '%s' "${_query_words[*]}")"

  # Collect files to search
  local -a _files=()
  local _f _dir

  if [[ "$_scope" == "all" ]]; then
    for _f in ".platform/architecture.md" ".platform/STATUS.md" ".platform/work/BRIEF.md"; do
      [[ -f "$_f" ]] && _files+=("$_f")
    done
  fi

  for _dir in ".platform/domains" ".platform/conventions" ".platform/memory"; do
    [[ "$_scope" == "all" ]] || [[ "$_dir" == ".platform/$_scope" ]] || continue
    [[ -d "$_dir" ]] || continue
    while IFS= read -r _f; do
      [[ -f "$_f" ]] && _files+=("$_f")
    done < <(find "$_dir" -maxdepth 1 -name "*.md" 2>/dev/null | sort)
  done

  (( ${#_files[@]} > 0 )) || die "No .platform/ context files found."

  local _use_rg=0
  command -v rg >/dev/null 2>&1 && _use_rg=1 || true

  local _file_count=0

  for _f in "${_files[@]}"; do
    local _matches=""
    if (( _use_rg )); then
      _matches="$(rg -i -C "$_context" --color=never --no-heading --no-context-separator \
        -e "$_pattern" "$_f" 2>/dev/null || true)"
    else
      _matches="$(grep -i -E -C "$_context" --color=never "$_pattern" "$_f" 2>/dev/null | awk '$0 != "--"' || true)"
    fi
    # Note: do not pipe through `head` here — the head() shell function in core/base.sh
    # overrides the system head command within this process.
    [[ -z "$_matches" ]] && continue
    (( _file_count++ ))

    if (( _quiet )); then
      say "$_f"
    else
      local _tok; _tok="$(estimate_tokens_for_file "$_f")"
      printf '\n%s%s%s  %s(~%d tokens full file)%s\n' \
        "$C_BOLD$C_CYAN" "$_f" "$C_RESET" "$C_DIM" "$_tok" "$C_RESET"
      printf '%s\n' "$_matches"
      printf '%s────%s\n' "$C_DIM" "$C_RESET"
    fi
  done

  if (( _file_count == 0 )); then
    warn "No matches for: ${C_BOLD}${_pattern}${C_RESET}"
    printf '  Searched %d .platform/ file(s).\n' "${#_files[@]}"
    return 0
  fi

  if (( _quiet == 0 )); then
    printf '\n'
    ok "Matched ${C_BOLD}${_file_count}${C_RESET} / ${#_files[@]} files — query: ${C_BOLD}${_query_words[*]}${C_RESET}"
  fi
}

_search_help() {
  cat <<'EOF'
ab search <query terms...> [flags]

Search .platform/ context files for relevant snippets before loading full files.
Each term is OR-matched (case-insensitive). Results show file path + surrounding
context lines + estimated token cost of the full file.

Use this instead of loading full domain or convention files — retrieve only
the relevant paragraphs for the current task.

OPTIONS
  -C N, --context N   Lines of context around each match (default: 3)
  -q, --quiet         Print matching file paths only (no previews)
  --domains           Search .platform/domains/ only
  --memory            Search .platform/memory/ only
  --conventions       Search .platform/conventions/ only
  -h, --help          Show this help

EXAMPLES
  ab search "event deduplication"
  ab search auth token session --domains
  ab search migration --memory -C 5
  ab search "file watcher" -q

SCOPE (default: all)
  All:          architecture.md + STATUS.md + BRIEF.md + domains/ + conventions/ + memory/
  --domains:    .platform/domains/*.md
  --memory:     .platform/memory/*.md
  --conventions .platform/conventions/*.md

NOTES
  - Prefers ripgrep (rg) when available; falls back to grep -E
  - Token count shown per matched file is the FULL file cost — actual snippet cost is much lower
  - For LLM use: load only the specific sections that matched, not the full file
EOF
}
