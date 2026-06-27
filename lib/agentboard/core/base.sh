# -----------------------------------------------------------------------------
# Colors (honors NO_COLOR, disables if stdout isn't a TTY)
# -----------------------------------------------------------------------------

if [[ -n "${NO_COLOR:-}" ]] || ! [[ -t 1 ]]; then
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
else
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
bold() { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
head() { printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '  %s●%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '  %s✖%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ask <prompt> [default] [hint]
# Prints hint (if given) on its own dim line, then the prompt with the default
# shown in [brackets]. Returns the user input (or default) on stdout.
ask() {
  local prompt="$1" default="${2:-}" hint="${3:-}" reply
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  if [[ -n "$default" ]]; then
    printf '  %s?%s %s%s%s %s[%s]%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$default" "$C_RESET" >&2
    read -r reply
    echo "${reply:-$default}"
  else
    printf '  %s?%s %s%s%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" >&2
    read -r reply
    echo "$reply"
  fi
}

ask_yes_no() {
  local prompt="$1" reply
  printf '  %s?%s %s%s%s %s[y/N]%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ask_yes_no_default <prompt> <default: Y|N> [hint]
# Same styling as ask_yes_no but with a configurable default. An empty reply
# returns the default. Supports a dim-line hint printed above the prompt.
ask_yes_no_default() {
  local prompt="$1" default="${2:-N}" hint="${3:-}" reply bracket
  if [[ "$default" =~ ^[Yy]$ ]]; then
    bracket="[Y/n]"
  else
    bracket="[y/N]"
  fi
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  printf '  %s?%s %s%s%s %s%s%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$bracket" "$C_RESET" >&2
  read -r reply
  if [[ -z "$reply" ]]; then
    [[ "$default" =~ ^[Yy]$ ]]
  else
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

today() { date +%F; }

# parse_token_budget <value>
# Accepts "4000", "4k", or "4K" and echoes the integer token count.
# Returns non-zero on malformed input.
parse_token_budget() {
  local raw="$1" lower
  lower="$(printf '%s' "$raw" | tr 'A-Z' 'a-z')"
  if [[ "$lower" =~ ^([0-9]+)k$ ]]; then
    printf '%s\n' "$(( ${BASH_REMATCH[1]} * 1000 ))"
    return 0
  fi
  if [[ "$lower" =~ ^([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# estimate_tokens_for_file <file>
# Rough heuristic: 1 token ≈ 4 bytes of English markdown. Echoes 0 if the
# file does not exist. Zero runtime deps.
estimate_tokens_for_file() {
  local file="$1" bytes
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return 0
  fi
  bytes="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
  [[ -z "$bytes" ]] && bytes=0
  printf '%s\n' "$(( bytes / 4 ))"
}

require_templates() {
  [[ -d "$TEMPLATES_PLATFORM" ]] || die "templates/platform/ not found at $TEMPLATES_PLATFORM"
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

normalize_kebab_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  printf '%s' "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

unique_nonempty_lines() {
  awk 'NF && !seen[$0]++'
}

join_lines_comma() {
  awk 'NF { out = out ? out ", " $0 : $0 } END { print out }'
}

agentboard_runtime_gitignore_block() {
  cat <<'EOF'
# agentboard:runtime-begin
.platform/events.jsonl
.platform/events-*.jsonl
.platform/events.jsonl.archive-*
.platform/.daemon-port
.platform/.file-change-state.lock
.platform/.file-change-state.lock.d/
.platform/.file-change-state.tsv
.platform/.file-locks.json
.platform/.locks/
.platform/.session-streams.tsv
.platform/.watch.pid
.platform/.watch/
.platform/graphify/cache/
agentboard.hud-status.json
# agentboard:runtime-end
EOF
}

agentboard_runtime_gitignore_is_current() {
  local gitignore="${1:-./.gitignore}" line
  [[ -f "$gitignore" ]] || return 1
  grep -q '^# agentboard:runtime-begin$' "$gitignore" || return 1
  grep -q '^# agentboard:runtime-end$' "$gitignore" || return 1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    grep -Fxq "$line" "$gitignore" || return 1
  done < <(agentboard_runtime_gitignore_block)
}

ensure_agentboard_runtime_gitignore() {
  local gitignore="${1:-./.gitignore}" tmp line
  tmp="$(mktemp)"

  if [[ -f "$gitignore" ]] && grep -q '^# agentboard:runtime-begin$' "$gitignore"; then
    awk '
      /^# agentboard:runtime-begin$/ { in_block = 1; next }
      /^# agentboard:runtime-end$/   { in_block = 0; next }
      !in_block { print }
    ' "$gitignore" > "$tmp"
  elif [[ -f "$gitignore" ]]; then
    cat "$gitignore" > "$tmp"
  fi

  if [[ -s "$tmp" ]]; then
    tail -c 1 "$tmp" 2>/dev/null | grep -q '^$' || printf '\n' >> "$tmp"
  fi
  if [[ -s "$tmp" ]]; then
    printf '\n' >> "$tmp"
  fi
  agentboard_runtime_gitignore_block >> "$tmp"
  mv "$tmp" "$gitignore"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

detect_shell_name() {
  local shell_path="${SHELL:-}"
  shell_path="${shell_path##*/}"
  case "$shell_path" in
    zsh|bash|fish) printf '%s\n' "$shell_path" ;;
    *) printf '%s\n' "zsh" ;;
  esac
}

default_user_bin_dir() {
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    printf '%s\n' "$XDG_BIN_HOME"
  elif [[ -d "$HOME/.local/bin" ]]; then
    printf '%s\n' "$HOME/.local/bin"
  elif [[ -d "$HOME/bin" ]]; then
    printf '%s\n' "$HOME/bin"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

shell_rc_file() {
  local shell_name="$1"
  case "$shell_name" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

shell_path_snippet() {
  local shell_name="$1" bin_dir="$2"
  case "$shell_name" in
    fish) printf 'fish_add_path "%s"\n' "$bin_dir" ;;
    *) printf 'export PATH="%s:$PATH"\n' "$bin_dir" ;;
  esac
}

path_contains_dir() {
  local dir="$1" entry
  IFS=':' read -r -a entries <<< "${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ "$entry" == "$dir" ]] && return 0
  done
  return 1
}
