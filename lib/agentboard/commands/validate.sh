# -----------------------------------------------------------------------------
# ab validate — check SKILL.md and role frontmatter for required fields.
#
# Scans .claude/skills/, templates/skills/, and .platform/roles/ for files
# with YAML frontmatter. Reports missing required fields and prints a summary.
# Pure bash 3.2 — no external deps beyond awk.
# -----------------------------------------------------------------------------

# _fm <file> <key> — extract a frontmatter value (empty string if absent)
_fm() {
  awk -v k="$2" '
    BEGIN{f=0;s=0}
    /^---[[:space:]]*$/{if(!s){s=1;f=1;next};if(f)exit}
    f && $0~("^"k":[[:space:]]*"){sub("^[^:]+:[[:space:]]*","");print;exit}
  ' "$1"
}

# _check_fields <file> <type> <field...> — warn on missing fields; echo count
_check_fields() {
  local _f="$1" _type="$2"; shift 2
  local _miss=0 _label _v
  _label="$(basename "$(dirname "$_f")")/$(basename "$_f")"
  [[ "$_type" == "role" ]] && _label="$(basename "$_f")"
  for _k in "$@"; do
    _v="$(_fm "$_f" "$_k")"
    if [[ -z "$_v" ]]; then
      warn "${_type} ${_label} — missing required field: $_k"
      _miss=$((_miss+1))
    fi
  done
  printf '%d' "$_miss"
}

cmd_validate() {
  local _sk=0 _sw=0 _rk=0 _rw=0 _m _f _dir

  head "Validating skill frontmatter"
  local -a _sdirs=()
  [[ -d ".claude/skills" ]] && _sdirs+=(".claude/skills")
  [[ -d "${AGENTBOARD_ROOT:-}/templates/skills" ]] && _sdirs+=("${AGENTBOARD_ROOT}/templates/skills")

  if (( ${#_sdirs[@]} == 0 )); then
    warn "No skill directories found (.claude/skills/ or templates/skills/)."
  else
    for _dir in "${_sdirs[@]}"; do
      while IFS= read -r _f; do
        [[ -f "$_f" ]] || continue
        if ! has_frontmatter "$_f"; then
          warn "skill $(basename "$(dirname "$_f")")/$(basename "$_f") — no YAML frontmatter"
          _sw=$((_sw+1)); continue
        fi
        _m="$(_check_fields "$_f" "skill" name description version origin)"
        if [[ "$_m" -eq 0 ]]; then
          ok "$(basename "$(dirname "$_f")")/$(basename "$_f")"; _sk=$((_sk+1))
        else
          _sw=$((_sw+1))
        fi
      done < <(find "$_dir" -name "SKILL.md" 2>/dev/null | sort)
    done
  fi

  head "Validating role frontmatter"
  if [[ ! -d ".platform/roles" ]]; then
    warn "No .platform/roles/ directory found — skipping role validation."
  else
    while IFS= read -r _f; do
      [[ -f "$_f" ]] || continue
      [[ "$(basename "$_f")" == "INDEX.md" ]] && continue
      if ! has_frontmatter "$_f"; then
        warn "role $(basename "$_f") — no YAML frontmatter"
        _rw=$((_rw+1)); continue
      fi
      _m="$(_check_fields "$_f" "role" name description routes_to)"
      if [[ "$_m" -eq 0 ]]; then
        ok "$(basename "$_f")"; _rk=$((_rk+1))
      else
        _rw=$((_rw+1))
      fi
    done < <(find ".platform/roles" -maxdepth 1 -name "*.md" 2>/dev/null | sort)
  fi

  printf '\n'
  say "${C_BOLD}Skills:${C_RESET} ${_sk} valid, ${_sw} with warnings"
  say "${C_BOLD}Roles:${C_RESET}  ${_rk} valid, ${_rw} with warnings"
  (( (_sw + _rw) == 0 )) && ok "All manifests valid." || return 1
}
