# -----------------------------------------------------------------------------
# ab brief --start — the session-start packet (target <= ~500 tokens).
#
# Replaces reading brief + BRIEF.md + ACTIVE.md + the reference-pack list: open
# streams with next actions, card names (newest first), the top gotchas, and a
# pointer line. Everything else is pulled on demand (ab recall / ab protocol).
# -----------------------------------------------------------------------------

BRIEF_START_MAX_STREAMS=6
BRIEF_START_MAX_CARDS=20
BRIEF_START_MAX_GOTCHAS=3

cmd_brief_start() {
  local project today_str f status slug next n=0 total=0
  today_str="$(today)"
  project="$(awk 'NR==1 { sub(/^# */, ""); print; exit }' ./.platform/STATUS.md 2>/dev/null)"
  [[ -n "$project" ]] || project="$(basename "$(pwd)")"
  printf '%sstart — %s (%s)%s\n' "$C_BOLD" "$project" "$today_str" "$C_RESET"

  printf 'Streams:\n'
  for f in ./.platform/work/*.md; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in ACTIVE.md|BRIEF.md|TEMPLATE.md) continue ;; esac
    has_frontmatter "$f" || continue
    status="$(frontmatter_value "$f" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    total=$((total + 1))
    (( n < BRIEF_START_MAX_STREAMS )) || continue
    slug="$(frontmatter_value "$f" "slug")"
    next="$(stream_next_action "$f")"
    [[ -n "$next" ]] || next="—"
    printf '  %s (%s) → %s\n' "$slug" "${status:-?}" "$(printf '%s' "$next" | cut -c1-110)"
    n=$((n + 1))
  done
  if (( total == 0 )); then printf '  none open — ask what to work on\n'
  elif (( total > n )); then printf '  +%d more: ab brief\n' "$((total - n))"
  fi

  _brief_start_cards
  _brief_start_gotchas
  printf 'On demand: ab recall <topic> [--layer L] · ab protocol [name] · ab brief (full)\n'
}

# newest cards first, names only
_brief_start_cards() {
  local f count=0 names
  names="$(for f in ./.platform/domains/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "TEMPLATE.md" ]] && continue
      printf '%s|%s\n' "$(frontmatter_value "$f" "updated_at" 2>/dev/null)" "$(basename "$f" .md)"
    done | sort -r | cut -d'|' -f2)"
  [[ -n "$names" ]] || return 0
  count="$(printf '%s\n' "$names" | wc -l | tr -d ' ')"
  printf 'Cards (%s): %s' "$count" "$(printf '%s\n' "$names" | awk -v m="$BRIEF_START_MAX_CARDS" 'NR<=m' | paste -sd' ' -)"
  (( count > BRIEF_START_MAX_CARDS )) && printf ' … +%d (ab recall --list)' "$((count - BRIEF_START_MAX_CARDS))"
  printf '\n'
}

_brief_start_gotchas() {
  local out
  [[ -f ./.platform/memory/gotchas.md ]] || return 0
  out="$({ grep '^🔴' ./.platform/memory/gotchas.md 2>/dev/null || true; } | sed 's/^🔴 never-forget · //; s/^🔴 //' | awk -v m="$BRIEF_START_MAX_GOTCHAS" 'NR<=m { print "  " substr($0,1,120) }')"
  [[ -n "$out" ]] && printf 'Never forget:\n%s\n' "$out"
  return 0
}
