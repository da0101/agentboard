# -----------------------------------------------------------------------------
# ab recall --affected [<base>] [--quiet] — which knowledge cards did your changes touch?
#
# Cards go stale when code changes without a stream: a bug fix, a refactor, a new
# feature. This reads what changed (committed since <base>, staged, unstaged,
# untracked — in the project and in every hub repo) and lists:
#   - cards that NAME a changed file and were not themselves updated: "still true?"
#   - changed files no card mentions: a new feature may need a card
# <base> defaults to each repo's upstream, else origin/develop|main|master. A base that
# does not exist in a repo is skipped there. Flags only — it never rewrites a card.
# --quiet prints one line, only when a card needs a look, and looks at this repo only (post-commit hook).
# Matching is by path suffix, like `ab recall --check`. Exit status is always 0.
# Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

# _aff_base <repo> <explicit> — the ref to compare against, or nothing
_aff_base() {
  local r="$1" b
  if [[ -n "${2:-}" ]]; then git -C "$r" rev-parse --verify -q "$2^{commit}" >/dev/null 2>&1 && printf '%s' "$2"; return 0; fi
  b="$(git -C "$r" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [[ -n "$b" ]] && { printf '%s' "$b"; return 0; }
  for b in origin/develop origin/main origin/master develop main master; do
    git -C "$r" rev-parse --verify -q "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
  done
  return 0
}

# _aff_changed <explicit-base> <out> [only-this-repo] — "rel<TAB>repo-dir<TAB>repo-id" per changed file (no .platform/, no noise)
_aff_changed() {
  local explicit="$1" out="$2" only="${3:-0}" r rid base name
  : > "$out"
  while IFS=$'\t' read -r r rid; do
    git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || continue
    name="$(basename "$r")"; base="$(_aff_base "$r" "$explicit")"
    { if [[ -n "$base" ]]; then git -C "$r" diff --name-only --no-renames "$base"...HEAD 2>/dev/null || git -C "$r" diff --name-only --no-renames "$base" HEAD 2>/dev/null || true; fi
      git -C "$r" diff --name-only --no-renames HEAD 2>/dev/null || true
      git -C "$r" ls-files -o --exclude-standard 2>/dev/null || true; } \
      | awk -v n="$name" -v id="$rid" 'NF && !seen[$0]++ && $0 !~ /(^|\/)(\.platform|node_modules|\.npm-cache|dist|build|vendor|coverage|\.next)\// && $0 !~ /(\.lock|-lock\.json|\.snap|\.DS_Store|\.min\.js|\.map)$/ { print $0 "\t" n "\t" id }' >> "$out"
  done < <(_recall_roots | awk -v only="$only" '!only || NR == 1')
}

cmd_recall_affected() {
  local explicit="" quiet=0 changed keys pairs hits f total n
  while [[ $# -gt 0 ]]; do
    case "$1" in --quiet) quiet=1 ;; --*) die "Unknown flag for recall --affected: $1" ;; *) explicit="$1" ;; esac; shift
  done
  changed="$(mktemp)"; keys="$(mktemp)"; pairs="$(mktemp)"; hits="$(mktemp)"
  _aff_changed "$explicit" "$changed" "$quiet"
  total="$(grep -c . "$changed" || true)"
  if (( total == 0 )); then (( quiet )) || say "Nothing changed${explicit:+ since $explicit} — no card can be stale from this."; rm -f "$changed" "$keys" "$pairs" "$hits"; return 0; fi

  # key -> file: every path suffix of rel, repo-dir/rel and repo-id/rel points at "repo-dir/rel"
  awk -F'\t' '{ disp = $2 "/" $1; for (v = 1; v <= 3; v++) { p = (v == 1) ? $1 : (v == 2) ? $2 "/" $1 : $3 "/" $1
      n = split(p, a, "/"); s = a[n]; print s "\t" disp; for (k = n - 1; k >= 1; k--) { s = a[k] "/" s; print s "\t" disp } } }' "$changed" | sort -u > "$keys"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    _recall_card_paths "$f" | awk -v c="$(basename "$f" .md)" '{ print c "\t" $0 }'
  done < <(_recall_cards) > "$pairs"
  # a sentinel line keeps every NR==FNR join below working when a file would be empty
  [[ -s "$pairs" ]] || printf -- '-\t-\n' > "$pairs"
  awk -F'\t' 'NR == FNR { disp[$1] = (($1 in disp) ? disp[$1] SUBSEP : "") $2; next }
      ($2 in disp) { n = split(disp[$2], d, SUBSEP); for (i = 1; i <= n; i++) print $1 "\t" d[i] }' "$keys" "$pairs" | sort -u > "$hits"
  printf -- '-\t-\n' >> "$hits"

  # cards updated in this very change (committed or not) are fine
  local updated; updated="$(mktemp)"
  { git diff --name-only --no-renames "${explicit:-HEAD}" 2>/dev/null; git diff --name-only HEAD 2>/dev/null; git ls-files -o --exclude-standard .platform/domains 2>/dev/null
    local b; b="$(_aff_base "." "$explicit")"; [[ -n "$b" ]] && git diff --name-only --no-renames "$b"...HEAD 2>/dev/null; } \
    | sed -n 's|^.*\.platform/domains/\(.*\)\.md$|\1|p' | sort -u > "$updated"
  printf -- '-\n' >> "$updated"

  local stale
  stale="$(awk -F'\t' 'NR == FNR { up[$1] = 1; next } $1 != "-" && !($1 in up) { c[$1]++; if (c[$1] <= 3) e[$1] = e[$1] (e[$1] == "" ? "" : ", ") $2 } END { for (k in c) printf "%s\t%d\t%s\n", k, c[k], e[k] }' "$updated" "$hits" | sort -t$'\t' -k2,2nr)"
  if (( quiet )); then
    [[ -n "$stale" ]] && printf 'ab: this change touches files named in card(s): %s — still accurate? (ab recall --affected)\n' "$(printf '%s\n' "$stale" | cut -f1 | paste -sd, - | sed 's/,/, /g')"
    rm -f "$changed" "$keys" "$pairs" "$hits" "$updated"; return 0
  fi
  printf '\n%s%sab recall --affected%s  %s changed file(s)%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$total" "${explicit:+ since $explicit}"
  if [[ -n "$stale" ]]; then
    printf '  Cards that name files you changed — are they still true?\n'
    printf '%s\n' "$stale" | awk -F'\t' '{ printf "    %-26s %2d file(s)   e.g. %s\n", $1, $2, $3 }'
  else say "  No un-updated card names a file you changed."; fi
  if [[ "$(grep -vc '^-$' "$updated" || true)" != 0 ]]; then printf '\n  Cards already updated in this change: %s\n' "$(grep -v '^-$' "$updated" | paste -sd, - | sed 's/,/, /g')"; fi
  n="$(awk -F'\t' 'NR == FNR { cov[$2] = 1; next } !(($2 "/" $1) in cov) { print $2 "/" $1 }' "$hits" "$changed" | grep -c . || true)"
  if (( n > 0 )); then
    printf '\n  %s changed file(s) that no card mentions — a new feature may need a card. Mostly in:\n' "$n"
    awk -F'\t' 'NR == FNR { cov[$2] = 1; next } !(($2 "/" $1) in cov) { k = split($1, a, "/"); d = $2; for (i = 1; i < k && i <= 3; i++) d = d "/" a[i]; if (k == 1) d = $2 "/"; c[d]++ }
      END { for (d in c) printf "%d\t%s\n", c[d], d }' "$hits" "$changed" | sort -rn | awk 'NR <= 5 { printf "    %-4s %s\n", $1, $2 }'
  fi
  printf '\n  Fix a card by editing it (or add "- [key] fact" to the stream'\''s Knowledge delta). Unchanged behavior needs nothing.\n'
  rm -f "$changed" "$keys" "$pairs" "$hits" "$updated"; return 0
}
