# -----------------------------------------------------------------------------
# ab route — which model for this task? One answer, from two small tables.
#
#   ab route                          show the whole routing table
#   ab route <type> [low|medium|high] recommend a tier and the model per provider
#   ab route <type> [cx] --for claude print just the model id (empty + exit 1 if unset)
#   ab route --types                  list task types
#
# routing.tsv maps (task type, complexity) -> tier; models.tsv maps tier -> model
# per provider. Project copies in .platform/ win over the kit defaults, so a
# model rename is a one-line edit. Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

_route_file() { # name -> project copy or kit default
  if [[ -f "./.platform/$1" ]]; then printf './.platform/%s' "$1"; else printf '%s/%s' "$TEMPLATES_PLATFORM" "$1"; fi
}

_route_norm_complexity() { # usage labels -> low|medium|high
  case "$(printf '%s' "${1:-medium}" | tr '[:upper:]' '[:lower:]')" in
    low|trivial|small|easy) echo low ;;
    medium|normal|med|moderate) echo medium ;;
    high|heavy|large|hard|complex) echo high ;;
    *) echo "$1" ;;
  esac
}

# _route_lookup <type> <complexity> — "tier<TAB>why", exact match first, then "*"
_route_lookup() {
  awk -F'\t' -v t="$1" -v c="$2" '
    /^#/ || NF < 3 { next }
    $1 == t && $2 == c { print $3 "\t" $4; found = 1; exit }
    $1 == t && $2 == "*" && !wild { wild = $3 "\t" $4 }
    END { if (!found && wild) print wild }' "$(_route_file routing.tsv)"
}

_route_model() { # <tier> <provider> -> model or "-"
  awk -F'\t' -v tier="$1" -v p="$2" '
    /^#/ { next }
    $1 == tier { col = (p == "claude" ? 2 : (p == "codex" ? 3 : (p == "gemini" ? 4 : 0))); print (col ? $col : "-"); exit }' "$(_route_file models.tsv)"
}

cmd_route() {
  local type="" cx="" for_p="" t tier why m p
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        say "Usage: ab route [<type> [low|medium|high]] [--for claude|codex|gemini] | --types"
        say "Tables: .platform/routing.tsv (type+complexity -> tier), .platform/models.tsv (tier -> model)."
        return 0 ;;
      --types)
        awk -F'\t' '!/^#/ && NF >= 3 { print $1 }' "$(_route_file routing.tsv)" | sort -u | paste -sd' ' -
        return 0 ;;
      --for) for_p="${2:-}"; shift 2 ;;
      -*) die "Unknown flag for route: $1" ;;
      *) if [[ -z "$type" ]]; then type="$1"; else cx="$1"; fi; shift ;;
    esac
  done

  if [[ -z "$type" ]]; then
    printf '  %s%-15s %-8s %-9s %-10s %s%s\n' "$C_DIM" "TYPE" "COMPLEX" "TIER" "CLAUDE" "WHY" "$C_RESET"
    awk -F'\t' '!/^#/ && NF >= 3 { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$(_route_file routing.tsv)" |
    while IFS=$'\t' read -r t c tier why; do
      printf '  %-15s %-8s %-9s %-10s %s\n' "$t" "$c" "$tier" "$(_route_model "$tier" claude)" "$why"
    done
    return 0
  fi

  cx="$(_route_norm_complexity "$cx")"
  m="$(_route_lookup "$type" "$cx")"
  if [[ -z "$m" ]]; then
    die "No route for task type '$type'. Types: $(cmd_route --types)"
  fi
  tier="${m%%$'\t'*}"; why="${m#*$'\t'}"

  if [[ -n "$for_p" ]]; then
    case "$for_p" in claude|codex|gemini) ;; *) die "--for must be claude, codex or gemini" ;; esac
    p="$(_route_model "$tier" "$for_p")"
    [[ -n "$p" && "$p" != "-" ]] || return 1
    printf '%s\n' "$p"; return 0
  fi

  printf '  %s%s%s (%s) → tier %s%s%s — %s\n' "$C_BOLD" "$type" "$C_RESET" "$cx" "$C_BOLD" "$tier" "$C_RESET" "$why"
  for p in claude codex gemini; do
    m="$(_route_model "$tier" "$p")"
    if [[ -z "$m" || "$m" == "-" ]]; then printf '    %-7s (not set — add a %s model for tier "%s" in .platform/models.tsv)\n' "$p" "$p" "$tier"
    else printf '    %-7s %s\n' "$p" "$m"; fi
  done
}
