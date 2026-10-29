# -----------------------------------------------------------------------------
# ab domain merge <target> <source...> [--title T] [--apply] — fold narrow
# domain cards into one feature card.
#
# Many small "concern" cards (care-plan-pdfs next to care-plans) make the card
# map big and hide the full-stack picture. Merging keeps every word:
#   - the target keeps its own sections; each source's text arrives as sections
#     headed "<Source title> — <original heading>", so `ab recall --layer backend`
#     still finds every backend section. A source's intro becomes
#     "<Source title> — overview".
#   - frontmatter: repo_ids union, created_at earliest, updated_at latest,
#     related_domain_slugs union (minus the merged slugs and the card itself).
#   - everything that pointed at a merged card is rewritten: domain_slugs on
#     streams, related_domain_slugs on cards, `domains/<old>.md` paths.
# Sources are copied to the cold store, then removed. Preview by default.
# Pure bash 3.2 + awk (reuses the frontmatter helpers of `ab repair domains`).
# -----------------------------------------------------------------------------

_dm_title() { awk '/^# /{ sub(/^# +(Domain *[:—-] *)?/, ""); print; exit }' "$1"; }
_dm_titlecase() { printf '%s' "$1" | tr '-' ' ' | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2) } 1'; }

# _dm_tokens <inline-array> — "a, b" -> one per line
_dm_tokens() { local v="${1#[}"; v="${v%]}"; printf '%s\n' "$v" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'"'"']//; s/["'"'"']$//' | awk 'NF'; }

# _dm_foreign_body <card> <label> — a source's body as sections of the target
_dm_foreign_body() {
  _rd_body "$1" | LABEL="$2" awk '
    BEGIN { label = ENVIRON["LABEL"]; seen = 0 }
    /^# / && !seen_h1 { seen_h1 = 1; next }
    /^## / { if (pre != "" && !emitted) { print "## " label " — overview"; printf "%s", pre; print ""; emitted = 1 }
             seen = 1; h = $0; sub(/^## */, "", h); print "## " label " — " h; next }
    !seen { if ($0 ~ /[^ \t]/ || pre != "") pre = pre $0 "\n"; next }
    { print }
    END { if (!seen && pre != "" ) { print "## " label " — overview"; printf "%s", pre } }'
}

# _dm_rewrite_refs <target> <old...> — repoint streams, cards, BRIEF and path mentions
_dm_rewrite_refs() {
  local target="$1" f olds tmp n=0; shift; olds="$*"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    tmp="$(mktemp)"
    TARGET="$target" OLDS="$olds" SELF="$(basename "$f" .md)" awk '
      BEGIN { t = ENVIRON["TARGET"]; n = split(ENVIRON["OLDS"], o, " "); for (i = 1; i <= n; i++) isold[o[i]] = 1; self = ENVIRON["SELF"] }
      NR == 1 && /^---[ \t]*$/ { fm = 1; print; next }
      fm && /^---[ \t]*$/ { fm = 0; print; next }
      fm && /^(domain_slugs|related_domain_slugs):/ {
        key = $0; sub(/:.*$/, "", key); v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/[\[\]]/, "", v)
        m = split(v, a, ","); out = ""; delete seen
        for (i = 1; i <= m; i++) { x = a[i]; gsub(/^[ \t"]+|[ \t"]+$/, "", x); if (x == "") continue
          if (x in isold) x = t
          if (key == "related_domain_slugs" && x == self) continue
          if (!(x in seen)) { seen[x] = 1; out = out (out == "" ? "" : ", ") x } }
        print key ": [" out "]"; next }
      { line = $0
        for (k in isold) { pat = "domains/" k ".md"; while ((i = index(line, pat)) > 0) line = substr(line, 1, i - 1) "domains/" t ".md" substr(line, i + length(pat)) }
        print line }' "$f" > "$tmp"
    if ! cmp -s "$tmp" "$f"; then mv "$tmp" "$f"; n=$((n + 1)); else rm -f "$tmp"; fi
  done < <(find ./.platform -name '*.md' -not -path '*/work/archive/*' -not -path '*/protocols/*' -not -path '*/roles/*' \
             -not -path '*/agents/*' -not -path '*/graphify/*' -not -name 'ACTIVATE*' -not -name workflow.md -not -name ONBOARDING.md -not -name RESCAN.md)
  printf '%s' "$n"
}

cmd_domain_merge() {
  local apply=0 title="" target="" s f label out cold primary="" repos="" created="9999-99-99" updated="0000-00-00" related="" status="active" tk blk
  local -a sources=() cards=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      --title) title="${2:-}"; shift 2 ;;
      -*) die "Unknown flag for domain merge: $1" ;;
      *) if [[ -z "$target" ]]; then target="$1"; else sources+=("$1"); fi; shift ;;
    esac
  done
  [[ -n "$target" && ${#sources[@]} -gt 0 ]] || die "Usage: ab domain merge <target> <source...> [--title T] [--apply]"
  [[ "$target" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Target slug must be kebab-case."
  [[ -d ./.platform/domains ]] || die "No .platform/domains/ found."
  for s in "${sources[@]}"; do [[ -f "./.platform/domains/$s.md" ]] || die "No such card: $s"; done
  [[ -f "./.platform/domains/$target.md" ]] && primary="$target"
  # order: the existing target first, then the others in the order given
  [[ -n "$primary" ]] && cards+=("$target")
  for s in "${sources[@]}"; do [[ "$s" == "$target" ]] || cards+=("$s"); done

  for s in "${cards[@]}"; do
    f="./.platform/domains/$s.md"; blk="$(_rd_block "$f")"
    while IFS= read -r tk; do
      if [[ -n "$tk" && ", $repos," != *", $tk,"* ]]; then repos="${repos:+$repos, }$tk"; fi
    done < <(_dm_tokens "$(_rd_get "$blk" repo_ids repos)")
    while IFS= read -r tk; do
      if [[ -n "$tk" && ", $related," != *", $tk,"* ]]; then related="${related:+$related, }$tk"; fi
    done < <(_dm_tokens "$(_rd_get "$blk" related_domain_slugs)")
    tk="$(_rd_get "$blk" created_at)"; [[ "$tk" =~ ^[0-9]{4}- && "$tk" < "$created" ]] && created="$tk"
    tk="$(_rd_get "$blk" updated_at)"; [[ "$tk" =~ ^[0-9]{4}- && "$tk" > "$updated" ]] && updated="$tk"
  done
  [[ "$created" != "9999-99-99" ]] || created="$(today)"; [[ "$updated" != "0000-00-00" ]] || updated="$(today)"
  # drop merged slugs (and the target itself) from the related list
  local keep="" drop
  while IFS= read -r tk; do
    if [[ -z "$tk" || "$tk" == "$target" ]]; then continue; fi
    drop=0; for s in "${sources[@]}"; do if [[ "$tk" == "$s" ]]; then drop=1; fi; done
    if (( ! drop )); then keep="${keep:+$keep, }$tk"; fi
  done < <(_dm_tokens "[$related]"); related="$keep"

  out="$(mktemp)"
  { printf -- '---\ndomain_id: dom-%s\nslug: %s\nstatus: %s\nrepo_ids: [%s]\nrelated_domain_slugs: [%s]\ncreated_at: %s\nupdated_at: %s\n---\n\n' \
      "$target" "$target" "$status" "$repos" "$related" "$created" "$updated"
    if [[ -n "$primary" ]]; then _rd_body "./.platform/domains/$target.md"
    else printf '# Domain: %s\n\n' "${title:-$(_dm_titlecase "$target")}"; fi
    for s in "${cards[@]}"; do
      if [[ "$s" == "$primary" ]]; then continue; fi
      label="$(_dm_title "./.platform/domains/$s.md")"; if [[ -z "$label" ]]; then label="$s"; fi
      printf '\n'; _dm_foreign_body "./.platform/domains/$s.md" "$label"
    done
  } > "$out"

  printf '\n%s%sab domain merge%s → %s %s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$target" "$( (( apply )) && echo '(applying)' || echo '(preview — add --apply)')"
  printf '  cards:   %s\n  repos:   [%s]\n  size:    %d B (≈ %d tokens) from %d card(s)\n' "${cards[*]}" "$repos" "$(wc -c < "$out" | tr -d ' ')" "$(( $(wc -c < "$out") / 4 ))" "${#cards[@]}"
  if (( ! apply )); then
    printf '  references that would be rewritten: '
    grep -rlE "domains/($(IFS='|'; echo "${sources[*]}"))\.md|(domain_slugs|related_domain_slugs):.*\b($(IFS='|'; echo "${sources[*]}"))\b" ./.platform --include='*.md' 2>/dev/null | grep -vE '/work/archive/|/protocols/|/roles/|/agents/' | wc -l | tr -d ' '
    rm -f "$out"; return 0
  fi

  cold="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")/domain-merge-$(today)"
  mkdir -p "$cold"
  for s in "${cards[@]}"; do cp -p "./.platform/domains/$s.md" "$cold/$s.md"; done
  mv "$out" "./.platform/domains/$target.md"
  local gone=()
  for s in "${sources[@]}"; do [[ "$s" == "$target" ]] || { rm -f "./.platform/domains/$s.md"; gone+=("$s"); }; done
  local n=0; (( ${#gone[@]} > 0 )) && n="$(_dm_rewrite_refs "$target" "${gone[@]}")"
  ok "Merged ${#gone[@]} card(s) into ${target}; rewrote references in ${n} file(s). Originals: $cold"
}

cmd_domain() {
  case "${1:-}" in
    merge) shift; cmd_domain_merge "$@" ;;
    -h|--help|"") say "Usage: ab domain merge <target> <source...> [--title T] [--apply]"; say "  Fold narrow domain cards into one feature card; rewrites every reference. Preview by default." ;;
    *) die "Unknown domain subcommand: $1 (merge)" ;;
  esac
}
