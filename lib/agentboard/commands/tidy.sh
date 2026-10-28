# -----------------------------------------------------------------------------
# ab tidy — bring any project to the lean layout. Report-only by default.
#
#   ab tidy [--days N] [--worktrees]     show what is polluting this project
#   ab tidy --apply [--worktrees]        do the safe subset
#
# Safe subset (never touches open streams, domains/, memory/, knowledge/):
#   - work/archive/, graphify/, memory/session-*.md  -> copied to the cold store
#     (~/.agentboard/cold/<project>/tidy-<date>/), then removed from the repo
#   - QA files whose stream no longer exists          -> same
#   - rotated event logs (gitignored telemetry)       -> removed
#   - closed rows left in work/ACTIVE.md              -> removed
#   - unmodified extra skills                         -> pruned (ab skill prune)
#   - kernel block in marker-managed entry files      -> synced (ab entry sync)
# Report-only (needs a human): stale streams, drifted cards, unmarked entry files,
# session-start budget. --worktrees also removes merged, clean worktrees.
# Removals show up in `git status`; review and commit when ready. Pure bash 3.2.
# -----------------------------------------------------------------------------

TIDY_ITEMS=0
TIDY_KB=0

_tidy_kb() { # paths -> total KB (0 if none exist)
  local p kb=0 n
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    n="$(du -sk "$p" 2>/dev/null | awk '{print $1}')"; kb=$((kb + ${n:-0}))
  done
  printf '%s' "$kb"
}

_tidy_cold_dest() {
  local root="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}" proj
  proj="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  printf '%s/%s/tidy-%s' "$root" "$proj" "$(today)"
}

# _tidy_cold <path> — copy under the cold store (path preserved), then remove
_tidy_cold() {
  local src="$1" dest rel
  dest="$(_tidy_cold_dest)"; rel="${src#./}"
  mkdir -p "$dest/$(dirname "$rel")"
  cp -pR "$src" "$dest/$rel" && rm -rf "$src"
}

# _tidy_item <apply> <title> <detail> <kind> <path...> — report, and act when applying
#   kind: cold (copy out then remove) | delete
_tidy_item() {
  local apply="$1" title="$2" detail="$3" kind="$4" p kb; shift 4
  kb="$(_tidy_kb "$@")"
  TIDY_ITEMS=$((TIDY_ITEMS + 1)); TIDY_KB=$((TIDY_KB + kb))
  printf '  %s%-34s%s %6d KB  %s\n' "$C_BOLD" "$title" "$C_RESET" "$kb" "$detail"
  (( apply )) || return 0
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    if [[ "$kind" == cold ]]; then _tidy_cold "$p"; else rm -rf "$p"; fi
  done
}

_tidy_closed_rows() { # count of closed/done rows in ACTIVE.md
  awk -F'|' 'function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s);return s}
    NF >= 6 && t($4) ~ /^(closed|done)$/ { n++ } END { print n + 0 }' ./.platform/work/ACTIVE.md 2>/dev/null
}

_tidy_drop_closed_rows() {
  local tmp; tmp="$(mktemp)"
  awk -F'|' 'function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s);return s}
    NF >= 6 && t($4) ~ /^(closed|done)$/ { next } { print }' ./.platform/work/ACTIVE.md > "$tmp" && mv "$tmp" ./.platform/work/ACTIVE.md
}

# stream slugs untouched for >= N days (report only)
_tidy_stale_streams() {
  local days="$1" f status upd slug today_s out=""
  today_s="$(today)"
  for f in ./.platform/work/*.md; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in ACTIVE.md|BRIEF.md|TEMPLATE.md) continue ;; esac
    has_frontmatter "$f" || continue
    status="$(frontmatter_value "$f" "status")"; case "$status" in done|closed|archived) continue ;; esac
    upd="$(frontmatter_value "$f" "updated_at")"; slug="$(frontmatter_value "$f" "slug")"
    [[ "$upd" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
    out="$out$(awk -v a="$upd" -v b="$today_s" -v d="$days" -v s="$slug" '
      function dn(x,  y,m,dd,era,yoe,doy,doe) { split(x, p, "-"); y=p[1]+0; m=p[2]+0; dd=p[3]+0
        if (m <= 2) y--; era=int(y/400); yoe=y-era*400; doy=int((153*(m+(m>2?-3:9))+2)/5)+dd-1
        doe=yoe*365+int(yoe/4)-int(yoe/100)+doy; return era*146097+doe }
      BEGIN { age = dn(b) - dn(a); if (age >= d) printf "%s (%dd) ", s, age }')"
  done
  printf '%s' "$out"
}

cmd_tidy() {
  local apply=0 days=21 worktrees=0 f d slug n stale
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      --worktrees) worktrees=1; shift ;;
      --days) days="${2:-}"; [[ "$days" =~ ^[0-9]+$ ]] || die "--days needs a number"; shift 2 ;;
      -h|--help) sed -n 2,22p "$AGENTBOARD_ROOT/lib/agentboard/commands/tidy.sh" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) die "Unknown flag for tidy: $1" ;;
    esac
  done
  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."
  TIDY_ITEMS=0; TIDY_KB=0
  printf '\n%s%sab tidy%s %s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$( (( apply )) && echo '(applying the safe subset)' || echo '(report only — nothing changed; add --apply)')"

  say "Repo pollution"
  if [[ -d ./.platform/work/archive ]] && [[ -n "$(find ./.platform/work/archive -type f -not -name .gitkeep 2>/dev/null | awk 'NR==1')" ]]; then
    n="$(find ./.platform/work/archive -type f -not -name .gitkeep | wc -l | tr -d ' ')"
    _tidy_item "$apply" "work/archive/" "$n archived stream/QA file(s); knowledge now lives in domain cards" cold ./.platform/work/archive
  fi
  [[ -d ./.platform/graphify ]] && _tidy_item "$apply" "graphify/" "generated code graph; stale unless refreshed on every commit" cold ./.platform/graphify
  local -a dumps=(); for f in ./.platform/memory/session-*.md; do [[ -f "$f" ]] && dumps+=("$f"); done
  (( ${#dumps[@]} > 0 )) && _tidy_item "$apply" "memory/session-*.md" "${#dumps[@]} session dump(s) — raw transcripts, not memory" cold "${dumps[@]}"
  local -a logs=(); for f in ./.platform/events-*.jsonl ./.platform/events.jsonl.archive-*; do [[ -f "$f" ]] && logs+=("$f"); done
  (( ${#logs[@]} > 0 )) && _tidy_item "$apply" "rotated event logs" "${#logs[@]} file(s) of gitignored telemetry" delete "${logs[@]}"

  local -a orphans=()
  for f in ./.platform/work/qa/*-manual-qa.md ./.platform/work/qa/*-execution-journal.md; do
    [[ -f "$f" ]] || continue
    slug="$(basename "$f")"; slug="${slug%-manual-qa.md}"; slug="${slug%-execution-journal.md}"
    [[ -f "./.platform/work/${slug}.md" ]] || orphans+=("$f")
  done
  for d in ./.platform/work/qa/evidence/* ./.platform/work/qa/artifacts/*; do
    [[ -d "$d" ]] || continue
    [[ -f "./.platform/work/$(basename "$d").md" ]] || orphans+=("$d")
  done
  (( ${#orphans[@]} > 0 )) && _tidy_item "$apply" "QA files of closed streams" "${#orphans[@]} item(s) whose stream no longer exists" cold "${orphans[@]}"

  n="$(_tidy_closed_rows)"
  if (( n > 0 )); then
    TIDY_ITEMS=$((TIDY_ITEMS + 1))
    printf '  %s%-34s%s %6s     %s\n' "$C_BOLD" "ACTIVE.md closed rows" "$C_RESET" "—" "$n row(s) listed but already closed"
    (( apply )) && _tidy_drop_closed_rows
  fi

  say; say "Context cost"
  local extras=0 etok=0 sd name
  for sd in "$TEMPLATES_SKILLS_EXTRA"/*/; do
    [[ -d "$sd" ]] || continue; name="$(basename "$sd")"
    if [[ -n "$(_skill_installed_in "$name")" ]]; then extras=$((extras + 1)); etok=$((etok + $(_skill_cost "${sd%/}"))); fi
  done
  if (( extras > 0 )); then
    TIDY_ITEMS=$((TIDY_ITEMS + 1))
    printf '  %s%-34s%s %6s     %s\n' "$C_BOLD" "extra skills installed" "$C_RESET" "—" "$extras skill(s), ≈ $etok tokens in every session prompt"
    (( apply )) && cmd_skill_prune --apply
  fi
  _entry_budget_eval
  printf '  %-34s %6s     session start ≈ %d tokens — %s (warn %d / fail %d)\n' "entry file budget" "—" "$ENTRY_TOTAL" "$ENTRY_STATUS" "$ENTRY_BUDGET_WARN" "$ENTRY_BUDGET_FAIL"
  if (( apply )); then cmd_entry_sync; else cmd_entry_sync --dry-run; fi

  say; say "Needs a human (never automatic)"
  stale="$(_tidy_stale_streams "$days")"
  [[ -z "$stale" ]] || printf '  stale streams (>= %sd untouched): %s\n' "$days" "$stale"
  _recall_stale_scan
  (( RECALL_STALE_PATHS == 0 )) || printf '  knowledge cards name %d path(s) matching no file → ab recall --check\n' "$RECALL_STALE_PATHS"
  if (( worktrees )); then
    if (( apply )); then cmd_worktree_clean --apply; else cmd_worktree_clean; fi
  else
    say "  worktrees: run 'ab worktree status' (or add --worktrees)"
  fi

  say
  if (( TIDY_ITEMS == 0 )); then ok "Nothing to tidy."; return 0; fi
  if (( apply )); then
    ok "Tidied: ≈ $((TIDY_KB / 1024)) MB left the repo. Copies are in $(_tidy_cold_dest). Review: git status"
  else
    printf '  %d item(s), ≈ %d MB. Re-run with --apply to do the safe subset.\n' "$TIDY_ITEMS" "$((TIDY_KB / 1024))"
  fi
  return 0
}
