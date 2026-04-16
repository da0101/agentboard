cmd_tui() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local active="./.platform/work/ACTIVE.md"
  [[ -f "$active" ]] || die "$active not found."

  local filter_status="" filter_owner="" filter_repo="" sort_key="updated" watch_secs=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)
        [[ -n "${2:-}" ]] || die "tui requires a value after --status"
        filter_status="$2"; shift 2 ;;
      --owner)
        [[ -n "${2:-}" ]] || die "tui requires a value after --owner"
        filter_owner="$2"; shift 2 ;;
      --repo)
        [[ -n "${2:-}" ]] || die "tui requires a value after --repo"
        filter_repo="$2"; shift 2 ;;
      --sort)
        [[ -n "${2:-}" ]] || die "tui requires a value after --sort"
        case "$2" in
          slug|type|status|owner|updated|branch) sort_key="$2"; shift 2 ;;
          *) die "Unknown --sort key: $2 (allowed: slug, type, status, owner, updated, branch)" ;;
        esac
        ;;
      --watch)
        [[ -n "${2:-}" ]] || die "tui requires a value after --watch"
        [[ "$2" =~ ^[0-9]+$ ]] || die "tui --watch requires an integer (seconds)"
        watch_secs="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: agentboard tui [--status <s>] [--owner <name>] [--repo <id>]
                      [--sort slug|type|status|owner|updated|branch]
                      [--watch <seconds>]

Read-only dashboard rendering work/ACTIVE.md plus per-stream branch info.
Filters are exact-match on the corresponding column.
--watch N redraws every N seconds (Ctrl-C to exit).
EOF
        return 0 ;;
      *) die "Unknown flag for tui: $1" ;;
    esac
  done

  if (( watch_secs > 0 )); then
    while true; do
      printf '\033[H\033[2J'
      _tui_render "$active" "$filter_status" "$filter_owner" "$filter_repo" "$sort_key"
      printf '\n%s%s(refreshing every %ss — Ctrl-C to exit)%s\n' "$C_DIM" "" "$watch_secs" "$C_RESET"
      sleep "$watch_secs"
    done
  else
    _tui_render "$active" "$filter_status" "$filter_owner" "$filter_repo" "$sort_key"
  fi
}

# _tui_render <active> <filter_status> <filter_owner> <filter_repo> <sort_key>
_tui_render() {
  local active="$1" f_status="$2" f_owner="$3" f_repo="$4" sort_key="$5"

  local rows="" row slug type status agent updated stream_file branch repo_ids match_repo
  while IFS='|' read -r slug type status agent updated; do
    [[ -z "$slug" ]] && continue
    if [[ -n "$f_status" && "$status" != "$f_status" ]]; then continue; fi
    if [[ -n "$f_owner"  && "$agent"  != "$f_owner"  ]]; then continue; fi

    stream_file="./.platform/work/${slug}.md"
    branch="-"
    repo_ids=""
    if [[ -f "$stream_file" ]] && has_frontmatter "$stream_file"; then
      branch="$(frontmatter_value "$stream_file" "git_branch")"
      [[ -z "$branch" ]] && branch="-"
      repo_ids="$(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")" | tr '\n' ',' | sed 's/,$//')"
    fi

    if [[ -n "$f_repo" ]]; then
      match_repo=0
      if [[ -n "$repo_ids" ]]; then
        local ri
        for ri in ${repo_ids//,/ }; do
          if [[ "$ri" == "$f_repo" ]]; then match_repo=1; break; fi
        done
      fi
      (( match_repo )) || continue
    fi

    rows+="${slug}|${type}|${status}|${agent}|${updated}|${branch}"$'\n'
  done < <(stream_rows_from_active "$active")

  local title="agentboard tui"
  [[ -n "$f_status" ]] && title="$title  status=$f_status"
  [[ -n "$f_owner"  ]] && title="$title  owner=$f_owner"
  [[ -n "$f_repo"   ]] && title="$title  repo=$f_repo"
  printf '\n%s%s%s%s\n' "$C_BOLD" "$C_CYAN" "$title" "$C_RESET"

  if [[ -z "$(printf '%s' "$rows" | tr -d '\n\t ')" ]]; then
    printf '  %s(no streams match)%s\n\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local sort_col
  case "$sort_key" in
    slug) sort_col=1 ;;
    type) sort_col=2 ;;
    status) sort_col=3 ;;
    owner) sort_col=4 ;;
    updated) sort_col=5 ;;
    branch) sort_col=6 ;;
  esac

  printf '%s' "$rows" | awk -F'|' -v sc="$sort_col" -v R="$C_RESET" -v B="$C_BOLD" \
    -v G="$C_GREEN" -v Y="$C_YELLOW" -v RD="$C_RED" -v D="$C_DIM" -v BL="$C_BLUE" '
    BEGIN { n = 0 }
    NF >= 6 { for (i=1;i<=6;i++) cell[n,i] = $i; n++ }
    END {
      hdr[1] = "STREAM"; hdr[2] = "TYPE"; hdr[3] = "STATUS"
      hdr[4] = "OWNER";  hdr[5] = "UPDATED"; hdr[6] = "BRANCH"
      for (i=1;i<=6;i++) w[i] = length(hdr[i])
      for (r=0;r<n;r++) for (i=1;i<=6;i++) if (length(cell[r,i]) > w[i]) w[i] = length(cell[r,i])

      # bubble sort (n is small)
      for (a=0;a<n-1;a++) for (b=0;b<n-1-a;b++) {
        if (cell[b,sc] > cell[b+1,sc]) {
          for (i=1;i<=6;i++) { t = cell[b,i]; cell[b,i] = cell[b+1,i]; cell[b+1,i] = t }
        }
      }

      printf "  %s", B
      for (i=1;i<=6;i++) printf "%-*s  ", w[i], hdr[i]
      printf "%s\n", R
      for (r=0;r<n;r++) {
        sc_val = cell[r,3]
        col = R
        if (sc_val == "in-progress") col = G
        else if (sc_val == "blocked") col = RD
        else if (sc_val == "awaiting-verification") col = Y
        else if (sc_val == "planning") col = BL
        printf "  "
        for (i=1;i<=6;i++) {
          if (i == 3) printf "%s%-*s%s  ", col, w[i], cell[r,i], R
          else if (i == 6) printf "%s%-*s%s  ", D, w[i], cell[r,i], R
          else printf "%-*s  ", w[i], cell[r,i]
        }
        printf "\n"
      }
    }
  '
  printf '\n'
}
