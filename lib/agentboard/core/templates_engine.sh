# -----------------------------------------------------------------------------
# Template substitution engine.
#
# sed-based replacement helpers for filling {{PLACEHOLDER}} tokens and literal
# template text in scaffolded files. All replacement values pass through
# sed_escape_replacement so user-supplied strings containing '\', '&', or '|'
# survive verbatim. Pure bash + sed — no runtime deps.
# -----------------------------------------------------------------------------

sed_escape_replacement() {
  # Escape sed replacement metacharacters so user-supplied values survive
  # verbatim: backslash first, then '&', then the '|' delimiter.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

substitute() {
  # substitute <file> KEY1 value1 KEY2 value2 ...
  local file="$1"; shift
  local key value value_esc
  while [[ $# -gt 0 ]]; do
    key="$1"; value="$2"; shift 2
    value_esc="$(sed_escape_replacement "$value")"
    sed -i.bak "s|{{${key}}}|${value_esc}|g" "$file"
    rm -f "${file}.bak"
  done
}

is_placeholder_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  [[ "$value" == "—" ]] && return 0
  [[ "$value" == "YYYY-MM-DD" ]] && return 0
  [[ "$value" =~ \<.*\> ]] && return 0
  [[ "$value" =~ _TODO_ ]] && return 0
  [[ "$value" =~ ^TBD ]] && return 0
  return 1
}

replace_template_literals() {
  local file="$1"; shift
  local old new new_esc
  while [[ $# -gt 0 ]]; do
    old="$1"; new="$2"; shift 2
    new_esc="$(sed_escape_replacement "$new")"
    sed -i.bak "s|$old|$new_esc|g" "$file"
  done
  rm -f "${file}.bak"
}

replace_frontmatter_line() {
  local file="$1" key="$2" value="$3"
  local value_esc
  value_esc="$(sed_escape_replacement "$value")"
  sed -i.bak -E "s|^${key}: .*|${key}: ${value_esc}|" "$file"
  rm -f "${file}.bak"
}
