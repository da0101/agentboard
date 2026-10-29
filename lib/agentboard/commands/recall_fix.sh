# -----------------------------------------------------------------------------
# ab recall --check --fix [--apply] [card...] — correct card paths that MOVED.
#
# A path that matches no file is "moved" when exactly one file anywhere in the
# card's repos has the same name; the card is then pointed at the new place.
# Deliberately conservative:
#   - mock / test / build directories (__mocks__, __tests__, node_modules, dist,
#     build) never count as a new home unless the old path was in one too
#   - several same-named files = ambiguous: listed, never guessed
#   - no same-named file = gone: listed for a human (fix it, or drop the fact
#     with a Knowledge delta "- [key] -")
#   - only whole path tokens are replaced, never a suffix of a longer path
# Preview by default; --apply copies the originals to the cold store first,
# rewrites the cards and bumps their updated_at. Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

# _fix_index <out> — "relative/path<TAB>repo-id" for every known file (no .platform/)
_fix_index() {
  local out="$1" r rid
  : > "$out"
  while IFS=$'\t' read -r r rid; do
    [[ -d "$r" ]] || continue
    { if git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then git -C "$r" ls-files -co --exclude-standard 2>/dev/null
      else (cd "$r" && find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||'); fi; } \
      | awk -v id="$rid" '$0 !~ /^\.platform\// { print $0 "\t" id }' >> "$out"
  done < <(_recall_roots)
}

# _fix_candidate <index> <path> — echoes the new path, or "AMBIGUOUS" / "GONE"
_fix_candidate() {
  local index="$1" p="$2" prefix="" rest r rid b hits n pre
  rest="$p"
  while IFS=$'\t' read -r r rid; do
    for pre in "$rid" "$(basename "$r")"; do
      if [[ "$p" == "$pre/"* ]]; then prefix="$pre/"; rest="${p#"$pre/"}"; break 2; fi
    done
  done < <(_recall_roots)
  b="$(basename "$rest")"
  hits="$(awk -F'\t' -v b="$b" -v orig="$p" '
    { n = split($1, s, "/"); if (s[n] != b) next
      if ($1 ~ /(^|\/)(__mocks__|__tests__|node_modules|dist|build)\// && orig !~ /(__mocks__|__tests__|node_modules|dist|build)\//) next
      if (!seen[$1]++) print $1 }' "$index")"
  n="$(printf '%s' "$hits" | grep -c . || true)"
  if (( n == 0 )); then echo GONE; elif (( n > 1 )); then echo AMBIGUOUS; else printf '%s%s' "$prefix" "$hits"; fi
}

# _fix_history <path> — what git says about a file that is not in the working tree:
#   "deleted <sha> <date>"  |  "only on another branch (<sha> <date>)"  |  "never in git history"
_fix_history() {
  local p="$1" rest r rid pre sha line del
  rest="$p"
  while IFS=$'\t' read -r r rid; do
    for pre in "$rid" "$(basename "$r")"; do [[ "$p" == "$pre/"* ]] && { rest="${p#"$pre/"}"; break 2; }; done
  done < <(_recall_roots)
  while IFS=$'\t' read -r r rid; do
    git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || continue
    del="$(git -C "$r" log --all --diff-filter=D -1 --format='%h %cs' -- "$rest" 2>/dev/null || true)"
    if [[ -n "$del" ]]; then printf 'deleted %s' "$del"; return 0; fi
    line="$(git -C "$r" log --all -1 --format='%h %cs' -- "$rest" 2>/dev/null || true)"
    if [[ -n "$line" ]]; then printf 'only on another branch (%s)' "$line"; return 0; fi
  done < <(_recall_roots)
  printf 'never in git history'
}

# _fix_replace <card> <old> <new> — replace whole-token occurrences only
_fix_replace() {
  local tmp; tmp="$(mktemp)"
  OLD="$2" NEW="$3" awk '
    BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; lo = length(old) }
    { line = $0; out = ""
      while ((i = index(line, old)) > 0) {
        before = (i > 1) ? substr(line, i - 1, 1) : ""; after = substr(line, i + lo, 1); after2 = substr(line, i + lo + 1, 1)
        ok = (before == "" || before !~ /[A-Za-z0-9_.\/-]/) && (after == "" || after !~ /[A-Za-z0-9_\/-]/) && !(after == "." && after2 ~ /[A-Za-z0-9]/)
        out = out substr(line, 1, i - 1) (ok ? new : old); line = substr(line, i + lo) }
      print out line }' "$1" > "$tmp" && mv "$tmp" "$1"
}

cmd_recall_fix() {
  local apply=0 list index out card path new fixed=0 amb=0 gone=0 f cold cards_fixed="" want
  while [[ "${1:-}" == "--apply" ]]; do apply=1; shift; done
  list="$(mktemp)"; index="$(mktemp)"
  if (( $# > 0 )); then for want in "$@"; do [[ -f "./.platform/domains/${want%.md}.md" ]] && printf './.platform/domains/%s.md\n' "${want%.md}" >> "$list"; done
  else _recall_cards > "$list"; fi
  out="$(_recall_missing "$list")"; rm -f "$list"
  if [[ -z "$out" ]]; then ok "Nothing to fix: every path in the cards resolves."; rm -f "$index"; return 0; fi
  _fix_index "$index"
  cold="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")/recall-fix-$(today)"
  printf '\n%s%sab recall --check --fix%s %s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$( (( apply )) && echo '(applying)' || echo '(preview — add --apply to write)')"
  : > "$index.gone"; : > "$index.amb"
  while IFS=$'\t' read -r card path; do
    [[ -n "$path" ]] || continue
    new="$(_fix_candidate "$index" "$path")"
    case "$new" in
      GONE)      gone=$((gone + 1)); printf '%s\t%s\n' "$card" "$path" >> "$index.gone" ;;
      AMBIGUOUS) amb=$((amb + 1)); printf '%s\t%s\n' "$card" "$path" >> "$index.amb" ;;
      *)         fixed=$((fixed + 1)); printf '  ~ %-34s %s\n      → %s\n' "$card" "$path" "$new"
                 if (( apply )); then
                   f="./.platform/domains/${card}.md"; mkdir -p "$cold"; [[ -f "$cold/$card.md" ]] || cp -p "$f" "$cold/$card.md"
                   _fix_replace "$f" "$path" "$new"; case " $cards_fixed " in *" $card "*) ;; *) cards_fixed="$cards_fixed $card" ;; esac
                 fi ;;
    esac
  done <<< "$out"
  for card in $cards_fixed; do replace_frontmatter_line "./.platform/domains/${card}.md" "updated_at" "$(today)" 2>/dev/null || true; done
  if (( amb > 0 )); then printf '\n  Ambiguous (same file name in several places) — decide by hand:\n'; awk -F'\t' '{ print "    " $1 ": " $2 }' "$index.amb"; fi
  if (( gone > 0 )); then
    printf '\n  Gone (no file with that name anywhere) — fix the card or drop the fact:\n'
    while IFS=$'\t' read -r card path; do printf '    %s: %s\n        git: %s\n' "$card" "$path" "$(_fix_history "$path")"; done < "$index.gone"
  fi
  printf '\n  %d path(s) %s, %d ambiguous, %d gone.' "$fixed" "$( (( apply )) && echo corrected || echo 'would be corrected')" "$amb" "$gone"
  (( apply )) && (( fixed > 0 )) && printf ' Originals in %s' "$cold"
  printf '\n'; rm -f "$index" "$index.gone" "$index.amb"; return 0
}
