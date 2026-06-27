# -----------------------------------------------------------------------------
# ab validate — check SKILL.md and role frontmatter for required fields.
#
# Scans .claude/skills/, templates/skills/, and .platform/roles/ for files
# with YAML frontmatter. Reports missing required fields and prints a summary.
# Pure bash 3.2 — no external deps beyond awk.
#
# Flags:
#   --ci   Suppress ANSI colors, prefix output with "agentboard-validate: ",
#          emit GitHub Actions ::error annotations, exit 1 on any failure.
# -----------------------------------------------------------------------------

# _fm <file> <key> — extract a frontmatter value (empty string if absent)
_fm() {
  awk -v k="$2" '
    BEGIN{f=0;s=0}
    /^---[[:space:]]*$/{if(!s){s=1;f=1;next};if(f)exit}
    f && $0~("^"k":[[:space:]]*"){sub("^[^:]+:[[:space:]]*","");print;exit}
  ' "$1"
}

# _ci_warn <message> — print plain warning (no color)
_ci_warn() { printf 'agentboard-validate: WARNING %s\n' "$1"; }

# _ci_annotation <file> <message> — emit GitHub Actions error annotation
_ci_annotation() { printf '::error file=%s::%s\n' "$1" "$2" >&2; }

# _check_fields <ci> <file> <type> <field...>
# Warns on missing fields. In CI mode also emits ::error annotations.
# Echoes the count of missing fields.
_check_fields() {
  local _ci="$1" _f="$2" _type="$3"; shift 3
  local _miss=0 _label _v
  _label="$(basename "$(dirname "$_f")")/$(basename "$_f")"
  [[ "$_type" == "role" ]] && _label="$(basename "$_f")"
  for _k in "$@"; do
    _v="$(_fm "$_f" "$_k")"
    if [[ -z "$_v" ]]; then
      if [[ "$_ci" == "1" ]]; then
        _ci_annotation "$_f" "Missing required frontmatter field: $_k"
      else
        warn "${_type} ${_label} — missing required field: $_k"
      fi
      _miss=$((_miss+1))
    fi
  done
  printf '%d' "$_miss"
}

# _validate_skills <ci> <sk_var> <sw_var>
# Scans skill directories; increments caller's counters via nameref-style
# output on stdout: two numbers "sk sw" separated by space.
_validate_skills() {
  local _ci="$1"
  local _sk=0 _sw=0 _m _f _dir
  local -a _sdirs=()
  [[ -d ".claude/skills" ]] && _sdirs+=(".claude/skills")
  [[ -d "${AGENTBOARD_ROOT:-}/templates/skills" ]] && _sdirs+=("${AGENTBOARD_ROOT}/templates/skills")

  if (( ${#_sdirs[@]} == 0 )); then
    if [[ "$_ci" == "1" ]]; then
      _ci_warn "No skill directories found (.claude/skills/ or templates/skills/)."
    else
      warn "No skill directories found (.claude/skills/ or templates/skills/)."
    fi
  else
    for _dir in "${_sdirs[@]}"; do
      while IFS= read -r _f; do
        [[ -f "$_f" ]] || continue
        local _lbl
        _lbl="$(basename "$(dirname "$_f")")/$(basename "$_f")"
        if ! has_frontmatter "$_f"; then
          if [[ "$_ci" == "1" ]]; then
            _ci_annotation "$_f" "No YAML frontmatter found"
          else
            warn "skill ${_lbl} — no YAML frontmatter"
          fi
          _sw=$((_sw+1)); continue
        fi
        _m="$(_check_fields "$_ci" "$_f" "skill" name description)"
        if [[ "$_m" -eq 0 ]]; then
          [[ "$_ci" != "1" ]] && ok "${_lbl}"
          _sk=$((_sk+1))
        else
          _sw=$((_sw+1))
        fi
      done < <(find "$_dir" -name "SKILL.md" 2>/dev/null | sort)
    done
  fi
  printf '%d %d' "$_sk" "$_sw"
}

# _validate_roles <ci>
# Scans .platform/roles/; prints "rk rw" on stdout.
_validate_roles() {
  local _ci="$1"
  local _rk=0 _rw=0 _m _f
  if [[ ! -d ".platform/roles" ]]; then
    if [[ "$_ci" == "1" ]]; then
      _ci_warn "No .platform/roles/ directory found — skipping role validation."
    else
      warn "No .platform/roles/ directory found — skipping role validation."
    fi
  else
    while IFS= read -r _f; do
      [[ -f "$_f" ]] || continue
      [[ "$(basename "$_f")" == "INDEX.md" ]] && continue
      local _lbl
      _lbl="$(basename "$_f")"
      if ! has_frontmatter "$_f"; then
        if [[ "$_ci" == "1" ]]; then
          _ci_annotation "$_f" "No YAML frontmatter found"
        else
          warn "role ${_lbl} — no YAML frontmatter"
        fi
        _rw=$((_rw+1)); continue
      fi
      _m="$(_check_fields "$_ci" "$_f" "role" slug name label ansi_color mission)"
      if [[ "$_m" -eq 0 ]]; then
        [[ "$_ci" != "1" ]] && ok "${_lbl}"
        _rk=$((_rk+1))
      else
        _rw=$((_rw+1))
      fi
    done < <(find ".platform/roles" -maxdepth 1 -name "*.md" 2>/dev/null | sort)
  fi
  printf '%d %d' "$_rk" "$_rw"
}

cmd_validate() {
  local _ci=0 _sk=0 _sw=0 _rk=0 _rw=0
  local _skill_out _role_out

  # Parse flags
  for _arg in "$@"; do
    [[ "$_arg" == "--ci" ]] && _ci=1
  done

  if [[ "$_ci" != "1" ]]; then
    head "Validating skill frontmatter"
  fi
  _skill_out="$(_validate_skills "$_ci")"
  _sk="${_skill_out%% *}"
  _sw="${_skill_out##* }"

  if [[ "$_ci" != "1" ]]; then
    head "Validating role frontmatter"
  fi
  _role_out="$(_validate_roles "$_ci")"
  _rk="${_role_out%% *}"
  _rw="${_role_out##* }"

  if [[ "$_ci" == "1" ]]; then
    local _total_invalid=$((_sw + _rw))
    printf 'agentboard-validate: %d skills valid, %d invalid\n' "$_sk" "$_sw"
    printf 'agentboard-validate: %d roles valid, %d invalid\n' "$_rk" "$_rw"
    (( _total_invalid == 0 )) && return 0 || return 1
  else
    printf '\n'
    say "${C_BOLD}Skills:${C_RESET} ${_sk} valid, ${_sw} with warnings"
    say "${C_BOLD}Roles:${C_RESET}  ${_rk} valid, ${_rw} with warnings"
    (( (_sw + _rw) == 0 )) && ok "All manifests valid." || return 1
  fi
}
