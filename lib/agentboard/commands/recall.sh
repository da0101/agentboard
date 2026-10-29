# -----------------------------------------------------------------------------
# ab recall — pull the right slice of project knowledge for a topic, cheaply.
#
#   ab recall <topic...> [--layer L]... [--budget N] [--top N] [--no-related]
#   ab recall --list
#
# Domain files (.platform/domains/*.md) are feature cards: frontmatter, a short
# summary, then one `## <layer>` section per layer (backend, web, mobile, ...).
# recall ranks cards against the topic, prints the best one, and can narrow to
# the sections whose heading matches --layer. Output is capped at --budget
# tokens (~4 chars each); when truncated it lists the sections left out.
# Pure bash 3.2 + awk/grep — stack-agnostic, no index required.
# -----------------------------------------------------------------------------

recall_usage() {
  cat <<'EOF'
Usage: ab recall <topic...> [--layer L]... [--budget N] [--top N] [--no-related]
       ab recall --list
       ab recall --index [--check]
       ab recall --check [card...]
       ab recall --check --fix [--apply] [--prune] [card...]
       ab recall --check --accept <card> <path> <reason...>

  <topic>        words matched against card names, titles and bodies
  --layer L      only sections whose "## heading" contains L (repeatable),
                 e.g. --layer backend --layer mobile
  --budget N     cap output at ~N tokens (default 1500)
  --top N        print the N best cards (default 1)
  --no-related   skip the matching learnings/decisions lines
  --list         one line per card: name, repos, size, summary — the map
  --index        write .platform/CARDS.md, the same map as plain markdown for agents without Agentboard
  --check        report file paths named in cards that no longer exist (drift)
  --check --accept  mark a deliberate mention (retired file, unmerged branch) so it stops being reported
  --check --fix  rewrite paths that moved (or changed JS/TS extension) to one unambiguous new
                 place; --prune also drops bullets that are only a git-confirmed deleted path
EOF
}

_recall_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# _recall_cards — card file paths (TEMPLATE.md excluded)
_recall_cards() {
  local f
  for f in ./.platform/domains/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "TEMPLATE.md" ]] && continue
    printf '%s\n' "$f"
  done
  return 0
}

_recall_title() { awk '/^# /{sub(/^# +(Domain: *)?/,""); print; exit}' "$1"; }

# first prose line after the H1 (markdown noise stripped, 110 chars max); when
# the card goes straight to a section, the first "## " heading stands in.
_recall_summary() {
  awk '
    /^# /{h=1; next}
    h && /^## /{ sub(/^## */,""); print "§ " substr($0,1,106); exit }
    h && /^(---|\||- |\*\*Priority)/{ next }
    h && NF {gsub(/[*`_>]/,""); print substr($0,1,110); exit}' "$1"
}

_recall_repos() {
  local v
  v="$(frontmatter_value "$1" "repo_ids" 2>/dev/null || true)"
  v="${v#[}"; v="${v%]}"
  printf '%s' "${v// /}"
}

_recall_tokens() { printf '%s' "$(( $(wc -c < "$1" | tr -d ' ') / 4 ))"; }

# _recall_score <file> <term...> — relevance score, 0 = no match
_recall_score() {
  local f="$1" slug title body n score=0 t; shift
  slug="$(basename "$f" .md)"
  title="$(_recall_lower "$(_recall_title "$f")")"
  for t in "$@"; do
    [[ "$slug" == "$t" ]] && score=$((score + 100))
    [[ "$slug" == *"$t"* ]] && score=$((score + 50))
    [[ "$title" == *"$t"* ]] && score=$((score + 30))
    n="$(grep -ci -- "$t" "$f" 2>/dev/null || true)"
    (( ${n:-0} > 20 )) && n=20
    score=$((score + ${n:-0}))
  done
  printf '%s' "$score"
}

# _recall_sections <file> <layer-regex> — frontmatter dropped; preamble kept
# only when no layer filter; otherwise just the matching "## " sections.
_recall_sections() {
  awk -v pat="$2" '
    NR==1 && /^---$/ { fm=1; next }
    fm && /^---$/ { fm=0; next }
    fm { next }
    /^## / { seen=1; insec = (pat=="" || tolower($0) ~ pat); if (insec) print; next }
    { if (!seen) { if (pat=="") print; next } if (insec) print }' "$1"
}

# _recall_cap <budget-tokens> — stdin → stdout capped at a line boundary
_recall_cap() {
  awk -v max=$(( $1 * 4 )) '{ n += length($0) + 1; if (n > max) { cut=1; exit } print } END { exit cut }'
}

cmd_recall_list() {
  local f slug
  printf '  %s%-28s %-30s %6s  %s%s\n' "$C_DIM" "CARD" "REPOS" "~TOK" "SUMMARY" "$C_RESET"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    slug="$(basename "$f" .md)"
    printf '  %-28s %-30s %6s  %s\n' "${slug:0:28}" "$(_recall_repos "$f" | cut -c1-30)" \
      "$(_recall_tokens "$f")" "$(_recall_summary "$f")"
  done < <(_recall_cards)
}

# _recall_related <slug> <term...> — up to 3 learnings/decisions mentioning the topic
_recall_related() {
  local slug="$1" t pat out="" kf; shift
  # light stemming (plural "s") so "questionnaires" also finds "Questionnaire ..."
  pat="${slug%s}"; for t in "$@"; do pat="$pat|${t%s}"; done
  for kf in ./.platform/knowledge/learnings.jsonl ./.platform/knowledge/decisions.jsonl; do
    [[ -f "$kf" ]] || continue
    # NB: the CLI defines a `head` function (heading printer) — use awk for line caps.
    out="$out$( { grep -iE -- "$pat" "$kf" 2>/dev/null || true; } | awk 'NR<=3' | sed -nE 's/.*"(title|topic)":"([^"]*)".*/  - \2/p')"$'\n'
  done
  out="$(printf '%s' "$out" | awk 'NF && ++n<=3')"
  [[ -n "$out" ]] && printf '\n### Related knowledge\n%s\n' "$out"
  return 0
}

cmd_recall() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."
  local budget=1500 top=1 related=1 list=0 f score t layer_re="" body outline
  local -a terms=() layers=() ranked=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    recall_usage; return 0 ;;
      --list)       list=1; shift ;;
      --index)      shift; cmd_recall_index "$@"; return $? ;;
      --check)      shift
                    case "${1:-}" in
                      --fix)    shift; cmd_recall_fix "$@" ;;
                      --accept) shift; cmd_recall_accept "$@" ;;
                      *)        cmd_recall_check "$@" ;;
                    esac
                    return 0 ;;
      --layer)      [[ -n "${2:-}" ]] || die "--layer needs a value"; layers+=("$(_recall_lower "$2")"); shift 2 ;;
      --budget)     [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--budget needs a number"; budget="$2"; shift 2 ;;
      --top)        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--top needs a number"; top="$2"; shift 2 ;;
      --no-related) related=0; shift ;;
      --*)          die "Unknown flag for recall: $1" ;;
      *)            terms+=("$(_recall_lower "$1")"); shift ;;
    esac
  done
  (( list )) && { cmd_recall_list; return 0; }
  (( ${#terms[@]} > 0 )) || die "Usage: ab recall <topic...> (or: ab recall --list)"

  if (( ${#layers[@]} > 0 )); then
    layer_re="$(IFS='|'; printf '%s' "${layers[*]}")"
  fi

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    score="$(_recall_score "$f" "${terms[@]}")"
    (( score > 0 )) && ranked+=("$(printf '%05d|%s' "$score" "$f")")
  done < <(_recall_cards)
  if (( ${#ranked[@]} == 0 )); then
    say "No card matches: ${terms[*]}. Try: ab recall --list"
    return 0
  fi

  local n=0 entry
  while IFS= read -r entry; do
    (( n < top )) || break
    f="${entry#*|}"
    n=$((n + 1))
    printf '## recall: %s  (repos: %s | updated %s | ~%s tokens full)\n' "$(basename "$f" .md)" \
      "$(_recall_repos "$f")" "$(frontmatter_value "$f" "updated_at" 2>/dev/null || true)" "$(_recall_tokens "$f")"
    body="$(_recall_sections "$f" "$layer_re")"
    if [[ -z "$body" ]]; then
      printf 'No section matches --layer %s. Sections:\n' "${layers[*]}"
      grep '^## ' "$f" | sed 's/^/  /'
      continue
    fi
    if printf '%s\n' "$body" | _recall_cap "$budget"; then :; else
      outline="$(printf '%s\n' "$body" | grep '^## ' | sed 's/^/  /' || true)"
      printf '\n… truncated at ~%s tokens. Narrow with --layer, or raise --budget. Sections:\n%s\n' "$budget" "$outline"
    fi
    if (( related )); then
      _recall_related "$(basename "$f" .md)" "${terms[@]}"
    fi
  done < <(printf '%s\n' "${ranked[@]}" | sort -r)
}
