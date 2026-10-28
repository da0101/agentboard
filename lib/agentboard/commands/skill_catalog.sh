# -----------------------------------------------------------------------------
# ab skill list | install <name...> | prune [--apply]
#
# The kit ships a small CORE set (templates/skills/) that `ab init` installs, and
# an opt-in EXTRAS catalog (templates/skills-extra/). Every installed skill puts
# its name and description into EVERY session's prompt (~40-80 tokens each), so
# unused skills are a standing tax. `list` shows what is installed and what it
# costs; `install` adds an extra; `prune` removes unmodified extras (dry-run by
# default; a skill you edited is kept). Pure bash 3.2.
# -----------------------------------------------------------------------------

SKILL_DIRS=(".claude/skills" ".agents/skills" ".codex/skills")

# _skill_src <name> — template dir for a core or extra skill ("" if unknown)
_skill_src() {
  if [[ -d "$TEMPLATES_SKILLS/$1" ]]; then printf '%s' "$TEMPLATES_SKILLS/$1"
  elif [[ -d "$TEMPLATES_SKILLS_EXTRA/$1" ]]; then printf '%s' "$TEMPLATES_SKILLS_EXTRA/$1"
  fi
}

# _skill_cost <skill-dir> — approx prompt tokens (name + description)
_skill_cost() {
  local d desc
  d="$(awk '/^description:/{sub(/^description: */,""); print; exit}' "$1/SKILL.md" 2>/dev/null)"
  desc="$(basename "$1")$d"
  printf '%s' "$(( (${#desc} + 4 + 3) / 4 ))"
}

_skill_installed_in() { # name -> dirs where installed (space separated)
  local d out=""
  for d in "${SKILL_DIRS[@]}"; do [[ -d "./$d/$1" ]] && out="$out $d"; done
  printf '%s' "${out# }"
}

cmd_skill_list() {
  local d name tier where cost tot=0 n=0 dir
  printf '  %s%-26s %-6s %5s  %s%s\n' "$C_DIM" "SKILL" "TIER" "~TOK" "INSTALLED IN" "$C_RESET"
  for tier in core extra; do
    if [[ "$tier" == core ]]; then dir="$TEMPLATES_SKILLS"; else dir="$TEMPLATES_SKILLS_EXTRA"; fi
    for d in "$dir"/*/; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"; where="$(_skill_installed_in "$name")"; cost="$(_skill_cost "${d%/}")"
      printf '  %-26s %-6s %5s  %s\n' "$name" "$tier" "$cost" "${where:-—}"
      if [[ -n "$where" ]]; then tot=$((tot + cost)); n=$((n + 1)); fi
    done
  done
  printf '\n  %d installed skill(s) ≈ %d tokens in every session prompt. Add: ab skill install <name> · Trim: ab skill prune\n' "$n" "$tot"
}

cmd_skill_install() {
  local name src d n=0
  (( $# > 0 )) || die "Usage: ab skill install <name...>"
  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."
  for name in "$@"; do
    src="$(_skill_src "$name")"
    [[ -n "$src" ]] || die "Unknown skill '$name'. See: ab skill list"
    for d in ".claude/skills" ".agents/skills"; do
      if [[ -e "./$d/$name" ]]; then continue; fi
      mkdir -p "./$d" && cp -R "$src" "./$d/$name" && n=$((n + 1))
    done
    ok "$name installed (~$(_skill_cost "$src") tokens per session)"
  done
}

cmd_skill_prune() {
  local apply=0 d name dir found=0 freed=0 counted=" "
  [[ "${1:-}" == "--apply" ]] && apply=1
  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."
  for d in "$TEMPLATES_SKILLS_EXTRA"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    for dir in "${SKILL_DIRS[@]}"; do
      [[ -d "./$dir/$name" ]] || continue
      if ! diff -rq "${d%/}" "./$dir/$name" >/dev/null 2>&1; then
        warn "$dir/$name was edited — kept"; continue
      fi
      found=$((found + 1))
      # a session loads one skills dir per provider, so count each skill once
      case "$counted" in *" $name "*) ;; *) counted="$counted$name "; freed=$((freed + $(_skill_cost "${d%/}"))) ;; esac
      if (( apply )); then rm -rf "./$dir/$name"; say "  removed $dir/$name"; else say "  would remove $dir/$name"; fi
    done
  done
  if (( found == 0 )); then say "  No unmodified extra skills installed."; return 0; fi
  if (( apply )); then ok "Removed ${found} skill copy(ies); ≈ ${freed} fewer tokens in every session prompt."
  else say "  ${found} copy(ies) would be removed (≈ ${freed} tokens per session). Re-run with --apply. Re-add any with: ab skill install <name>"; fi
}
