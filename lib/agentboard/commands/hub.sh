# -----------------------------------------------------------------------------
# ab hub — let agents opened in a hub's sibling repos find the hub, without
# adding a single file to those repos.
#
#   ab hub register [--dry-run]   (run in the hub) record its repos in ~/.agentboard/hubs.tsv
#   ab hub unregister             forget this hub
#   ab hub list                   show the registry
#   ab hub install [--apply]      add the user-level Claude/Codex hooks (preview by default)
#   ab hub uninstall [--apply]    remove them again
#   ab hub check [path]           what would the hooks do in <path>?  (default: here)
#
# The hooks (lib/agentboard/hooks/hub-route.sh) read the registry: SessionStart prints the hub's
# start packet inside a registered repo; PreToolUse refuses edits to CLAUDE.md / AGENTS.md /
# GEMINI.md / .claude/ there. Registry line: "<repo root>\t<hub>\t<repo id>". Pure bash 3.2.
# -----------------------------------------------------------------------------

_hub_file() { printf '%s' "${AB_HUBS_FILE:-$HOME/.agentboard/hubs.tsv}"; }

# _hub_rows <hub> — "root<TAB>hub<TAB>id" for every existing repo in the hub's repos.md.
# A path that does not exist here (another machine, another username) falls back to a folder of the
# same name next to the hub.
_hub_rows() {
  local hub="$1" row id path abs
  [[ -f "$hub/.platform/repos.md" ]] || return 0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    id="${row%%|*}"; path="$(printf '%s' "$row" | cut -d'|' -f2)"
    case "$path" in "~"/*) path="$HOME/${path#\~/}" ;; esac
    abs="$(cd "$hub" 2>/dev/null && cd "$path" 2>/dev/null && pwd -P)" || abs="$(cd "$hub/../$(basename "$path")" 2>/dev/null && pwd -P)" || continue
    [[ "$abs" == "$hub" ]] && continue
    printf '%s\t%s\t%s\n' "$abs" "$hub" "$id"
  done < <(repo_rows_from_registry "$hub/.platform/repos.md")
}

# _hub_drop <file> <hub> — remove every line of this hub
_hub_drop() {
  local f="$1" tmp; [[ -f "$f" ]] || return 0
  tmp="$(mktemp)"; H="$2" awk -F'\t' '$2 != ENVIRON["H"]' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_hub_register() {
  local dry=0 hub f rows n
  [[ "${1:-}" == "--dry-run" ]] && dry=1
  [[ -f ./.platform/repos.md ]] || die "Run this inside a hub: no .platform/repos.md here."
  hub="$(pwd -P)"; f="$(_hub_file)"
  rows="$(_hub_rows "$hub")"
  [[ -n "$rows" ]] || die "No existing repo paths found in .platform/repos.md — nothing to register."
  n="$(printf '%s\n' "$rows" | grep -c . || true)"
  printf '\n%s%sab hub register%s %s — %s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$( (( dry )) && echo '(dry run)' || echo "→ $f")" "$hub"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "  %-22s %s\n", $3, $1 }'
  (( dry )) && { say; say "  $n repo(s) would be registered."; return 0; }
  mkdir -p "$(dirname "$f")"; _hub_drop "$f" "$hub"; printf '%s\n' "$rows" >> "$f"
  ok "$n repo(s) registered. Next: ab hub install   (adds the user-level hooks)"
}

cmd_hub_unregister() {
  local hub f; [[ -f ./.platform/repos.md ]] || die "Run this inside a hub."
  hub="$(pwd -P)"; f="$(_hub_file)"; _hub_drop "$f" "$hub"; ok "Hub $hub removed from $f"
}

cmd_hub_list() {
  local f; f="$(_hub_file)"
  if [[ ! -s "$f" ]]; then say "No hubs registered. In a hub: ab hub register"; return 0; fi
  awk -F'\t' '{ printf "  %-22s %-60s → %s\n", $3, $1, $2 }' "$f"
}

# ab hub check [path] — dry-run both hooks as the agents would see them
cmd_hub_check() {
  local dir script out rc root
  dir="$(cd "${1:-.}" 2>/dev/null && pwd -P)" || die "No such directory: ${1:-.}"
  script="$AGENTBOARD_ROOT/lib/agentboard/hooks/hub-route.sh"
  out="$(printf '{"cwd":"%s"}' "$dir" | bash "$script" session 2>&1 | awk 'NR <= 6')"
  if [[ -z "$out" ]]; then say "  $dir is not inside a registered repo — the hooks do nothing here."; return 0; fi
  printf '  SessionStart would print:\n%s\n  …\n' "$(printf '%s\n' "$out" | sed 's/^/    /')"
  for root in CLAUDE.md AGENTS.md GEMINI.md .claude/settings.json; do
    printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/%s"}}' "$dir" "$dir" "$root" | bash "$script" guard >/dev/null 2>&1 && rc=0 || rc=$?
    printf '  edit %-22s %s\n' "$root" "$( (( rc == 2 )) && echo 'BLOCKED' || echo 'allowed' )"
  done
}

cmd_hub() {
  case "${1:-}" in
    register)   shift; cmd_hub_register "$@" ;;
    unregister) shift; cmd_hub_unregister "$@" ;;
    list)       shift; cmd_hub_list "$@" ;;
    install)    shift; cmd_hub_install "$@" ;;
    uninstall)  shift; cmd_hub_install --remove "$@" ;;
    check)      shift; cmd_hub_check "$@" ;;
    -h|--help|"") sed -n 2,16p "$AGENTBOARD_ROOT/lib/agentboard/commands/hub.sh" | sed 's/^# \{0,1\}//' ;;
    *) die "Unknown hub subcommand: $1 (register, unregister, list, install, uninstall, check)" ;;
  esac
}
