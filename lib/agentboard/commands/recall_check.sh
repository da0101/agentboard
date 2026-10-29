# -----------------------------------------------------------------------------
# ab recall --check [card...] — find knowledge-card drift.
#
# Cards name files in `backticks`. When a file is renamed or deleted, the card
# keeps lying to every future agent. This lists, per card, the file paths that
# match NO file in the project or any hub repo.
#
# Cards often abbreviate (`wibbi/PatientList.jsx` for `src/components/wibbi/...`),
# so a path counts as present when any known file ENDS with it. One file index
# (git ls-files, incl. untracked) is built per run and every card is checked in a
# single awk pass. Heuristic and informational: exit status is always 0, and
# `ab doctor` surfaces only the count. Only clear file paths are considered
# (a "/", a file extension, no globs/placeholders); :line, ::symbol, #frag are
# stripped. Pure bash 3.2 + awk (no interval regexes: old BSD awk lacks them).
# -----------------------------------------------------------------------------

RECALL_STALE_PATHS=0
RECALL_STALE_CARDS=0

# _recall_card_paths <card> — unique candidate file paths, one per line
_recall_card_paths() {
  awk '
    NR == 1 && /^---$/ { fm = 1; next }
    fm && /^---$/ { fm = 0; next }
    fm { next }
    {
      line = $0
      while (match(line, /`[^`]+`/)) {
        span = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
        sub(/::.*$/, "", span); sub(/#.*$/, "", span); sub(/:[0-9]+(-[0-9]+)?$/, "", span); sub(/\(.*$/, "", span)
        if (span !~ /\//) continue
        if (span ~ /^(https?|ftp|git|ssh):/ || span ~ /^~/ || span ~ /^\.\.\./) continue
        if (span ~ /[*<>{}$| ,;=]/ || span !~ /^[A-Za-z0-9_.@\/+-]+$/) continue
        if (span !~ /\.[A-Za-z][A-Za-z0-9]*$/) continue          # extension starts with a letter: 6.5.3 is a version, not a file
        ext = span; sub(/^.*\./, "", ext); if (length(ext) > 8) continue
        print span
      }
    }' "$1" | sort -u
}

# _recall_roots — "path<TAB>repo-id" for the project root and every hub repo
_recall_roots() {
  local repos_file="./.platform/repos.md" root rows row rpath rid resolved
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  printf '%s\t%s\n' "$root" "$(basename "$root")"
  [[ -f "$repos_file" ]] || return 0
  rows="$(repo_rows_from_registry "$repos_file")"
  [[ -n "$rows" ]] || return 0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    rid="$(printf '%s' "$row" | cut -d'|' -f1)"
    rpath="$(printf '%s' "$row" | cut -d'|' -f2)"
    resolved="$(resolve_repo_path "$repos_file" "$rpath" 2>/dev/null || true)"
    if [[ -n "$resolved" && -d "$resolved" ]]; then printf '%s\t%s\n' "$resolved" "$rid"; fi
  done <<< "$rows"
  return 0
}

# _recall_build_index <out> — every known file as "relative/path", "RepoDir/relative/path"
# and "repo-id/relative/path", so card entries written either way resolve.
_recall_build_index() {
  local out="$1" r rid name
  : > "$out"
  while IFS=$'\t' read -r r rid; do
    [[ -d "$r" ]] || continue
    name="$(basename "$r")"
    if git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$r" ls-files -co --exclude-standard 2>/dev/null
    else
      (cd "$r" && find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||')
    fi | awk -v n="$name" -v id="$rid" '{ print; print n "/" $0; if (id != n) print id "/" $0 }' >> "$out"
  done < <(_recall_roots)
}

# _recall_missing <cards-file> — prints "card<TAB>path" for each path matching no file
_recall_missing() {
  local cards_file="$1" cand index f name p
  cand="$(mktemp)"; index="$(mktemp)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    name="$(basename "$f" .md)"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if [[ "$p" == /* ]]; then
        [[ -e "$p" ]] || printf '%s\t%s\n' "$name" "$p"
      else
        printf '%s\t%s\n' "$name" "$p" >> "$cand"
      fi
    done < <(_recall_card_paths "$f")
  done < "$cards_file"
  [[ -s "$cand" ]] || { rm -f "$cand" "$index"; return 0; }   # empty first file would break NR==FNR below
  _recall_build_index "$index"
  awk -F'\t' '
    NR == FNR { want[$2] = 1; next }                      # pass 1: candidate paths
    FILENAME == ARGV[2] {                                  # pass 2: file index
      n = split($0, part, "/"); s = part[n]; if (s in want) found[s] = 1
      for (k = n - 1; k >= 1; k--) { s = part[k] "/" s; if (s in want) found[s] = 1 }
      next }
    { if (!($2 in found)) print $1 "\t" $2 }               # pass 3: report
  ' "$cand" "$index" "$cand" | _recall_drop_accepted
  rm -f "$cand" "$index"
}

# Deliberate mentions (a retired file, a git-ignored snapshot, work on an unmerged branch)
# are recorded in .platform/drift-ignore as "card:path  # date reason" (or just "path").
# stdin "card<TAB>path" -> same, minus the accepted ones.
_recall_drop_accepted() {
  local ign="./.platform/drift-ignore"
  if [[ -s "$ign" ]]; then      # non-empty only: with an empty file awk's NR==FNR trick would swallow the data
    awk -F'\t' 'NR == FNR { sub(/[ \t]*#.*$/, "", $0); gsub(/^[ \t]+|[ \t]+$/, "", $0); if ($0 != "") ok[$0] = 1; next }
                 !(($1 ":" $2) in ok) && !($2 in ok) { print }' "$ign" -
  else cat; fi
}

# ab recall --check --accept <card> <path> [reason...]
cmd_recall_accept() {
  local card="${1:-}" file="${2:-}" reason
  [[ -n "$card" && -n "$file" ]] || die "Usage: ab recall --check --accept <card> <path> [reason...]"
  [[ -f "./.platform/domains/${card%.md}.md" ]] || die "No such card: $card"
  shift 2; reason="$*"
  [[ -n "$reason" ]] || die "Say why (the next reader needs it): ab recall --check --accept $card $file <reason>"
  printf '%s:%s  # %s %s\n' "${card%.md}" "$file" "$(today)" "$reason" >> ./.platform/drift-ignore
  ok "Accepted: ${card%.md}: $file (recorded in .platform/drift-ignore)"
}

# _recall_stale_scan — totals over every card (used by doctor)
_recall_stale_scan() {
  local list out
  RECALL_STALE_PATHS=0; RECALL_STALE_CARDS=0
  list="$(mktemp)"; _recall_cards > "$list"
  out="$(_recall_missing "$list")"; rm -f "$list"
  [[ -n "$out" ]] || return 0
  RECALL_STALE_PATHS="$(printf '%s\n' "$out" | grep -c .)"
  RECALL_STALE_CARDS="$(printf '%s\n' "$out" | cut -f1 | sort -u | grep -c .)"
  return 0
}

cmd_recall_check() {
  local list want out name total_paths=0 cards=0 stale cards_stale=0 total_stale=0 n n_paths
  list="$(mktemp)"
  if (( $# > 0 )); then
    for want in "$@"; do
      [[ -f "./.platform/domains/${want%.md}.md" ]] && printf './.platform/domains/%s.md\n' "${want%.md}" >> "$list"
    done
  else
    _recall_cards > "$list"
  fi
  cards="$(grep -c . "$list" || true)"
  if (( cards == 0 )); then rm -f "$list"; say "No matching cards."; return 0; fi
  while IFS= read -r want; do [[ -n "$want" ]] && total_paths=$((total_paths + $(_recall_card_paths "$want" | grep -c . || true))); done < "$list"
  out="$(_recall_missing "$list")"; rm -f "$list"
  if [[ -z "$out" ]]; then
    ok "All ${total_paths} file path(s) across ${cards} card(s) resolve to a real file$( [[ -f ./.platform/drift-ignore ]] && printf ' (or are accepted in .platform/drift-ignore)')."
    return 0
  fi
  for name in $(printf '%s\n' "$out" | cut -f1 | sort -u); do
    stale="$(printf '%s\n' "$out" | awk -F'\t' -v c="$name" '$1 == c { print $2 }')"
    n="$(printf '%s\n' "$stale" | grep -c .)"
    n_paths="$(_recall_card_paths "./.platform/domains/${name}.md" | grep -c . || true)"
    printf '  %s%s%s — %d of %d path(s) match no file\n' "$C_BOLD" "$name" "$C_RESET" "$n" "$n_paths"
    printf '%s\n' "$stale" | sed 's/^/      - /'
    total_stale=$((total_stale + n)); cards_stale=$((cards_stale + 1))
  done
  printf '\n  %d path(s) match no file, in %d of %d card(s). Fix the card, or drop the fact with a Knowledge delta (- [key] -).\n' \
    "$total_stale" "$cards_stale" "$cards"
  return 0
}
