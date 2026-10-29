# -----------------------------------------------------------------------------
# ab hub install [--apply] [--remove] — add (or remove) the user-level hooks that
# route agents from a hub's sibling repos to the hub.
#
#   ~/.claude/settings.json   SessionStart + PreToolUse entries (edited with python3 if present;
#                             otherwise the exact snippet is printed to paste)
#   ~/.codex/config.toml      one marked block appended at the end (removed again by --remove)
#
# Preview by default. --apply backs each file up to ~/.agentboard/backups/ first. Idempotent:
# entries are recognised by the hub-route.sh path. HOME is honoured, so tests never touch the real one.
# -----------------------------------------------------------------------------

HUB_TOML_BEGIN="# >>> agentboard hub-route >>>"
HUB_TOML_END="# <<< agentboard hub-route <<<"

_hub_script() { printf '%s/lib/agentboard/hooks/hub-route.sh' "$AGENTBOARD_ROOT"; }

_hub_toml_block() {
  local s; s="$(_hub_script)"
  cat <<EOT
$HUB_TOML_BEGIN
# Added by 'ab hub install'. Remove with 'ab hub uninstall'. Codex asks you to trust these once (/hooks).
[[hooks.SessionStart]]
matcher = "startup|resume|clear|compact"

[[hooks.SessionStart.hooks]]
type = "command"
command = '$s session'
timeout = 30
statusMessage = "Loading hub context"

[[hooks.PreToolUse]]
matcher = "^(Bash|apply_patch|Edit|Write)\$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = '$s guard'
timeout = 10
$HUB_TOML_END
EOT
}

_hub_backup() {
  local f="$1" dir="$HOME/.agentboard/backups"
  [[ -f "$f" ]] || return 0
  mkdir -p "$dir" && cp -p "$f" "$dir/$(basename "$f").$(date +%Y%m%d-%H%M%S)"
  printf '%s' "$dir"
}

# Claude settings.json: python3 does the JSON edit; mode add|remove|check. Prints a one-line verdict.
_hub_claude_edit() {
  local file="$1" mode="$2" script="$3" apply="$4"
  command -v python3 >/dev/null 2>&1 || { echo "NO_PYTHON"; return 0; }
  F="$file" M="$mode" S="$script" A="$apply" python3 -I - <<'PYEOF'
import json, os, sys
f, mode, script, apply = os.environ["F"], os.environ["M"], os.environ["S"], os.environ["A"] == "1"
try:
    data = json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {}
except Exception as e:
    print("BAD_JSON " + str(e)); sys.exit(0)
hooks = data.setdefault("hooks", {}) if isinstance(data, dict) else {}
mine = lambda h: "hub-route.sh" in str(h.get("command", ""))
entries = {"SessionStart": ("", script + " session"),
           "PreToolUse": ("Edit|Write|MultiEdit|NotebookEdit|Bash", script + " guard")}
changed = 0
for ev, (matcher, cmd) in entries.items():
    groups = hooks.get(ev, [])
    present = any(mine(h) for g in groups for h in g.get("hooks", []))
    if mode == "add" and not present:
        groups.append({"matcher": matcher, "hooks": [{"type": "command", "command": cmd}]}); changed += 1
    if mode == "remove" and present:
        for g in groups: g["hooks"] = [h for h in g.get("hooks", []) if not mine(h)]
        groups = [g for g in groups if g.get("hooks")]; changed += 1
    if groups: hooks[ev] = groups
    elif ev in hooks: del hooks[ev]
if mode == "remove" and not hooks: data.pop("hooks", None)
if apply and changed:
    with open(f, "w") as fh: json.dump(data, fh, indent=2); fh.write("\n")
print("CHANGED %d" % changed if changed else "UNCHANGED")
PYEOF
}

cmd_hub_install() {
  local apply=0 remove=0 claude codex script res bdir tmp
  while [[ $# -gt 0 ]]; do
    case "$1" in --apply) apply=1 ;; --remove) remove=1 ;; *) die "Unknown flag for hub install: $1" ;; esac; shift
  done
  claude="$HOME/.claude/settings.json"; codex="$HOME/.codex/config.toml"; script="$(_hub_script)"
  [[ -f "$script" ]] || die "Hook script missing: $script"
  printf '\n%s%sab hub %s%s %s\n\n' "$C_BOLD" "$C_CYAN" "$( (( remove )) && echo uninstall || echo install)" "$C_RESET" "$( (( apply )) && echo '(applying)' || echo '(preview — add --apply to write)')"

  # --- Claude Code ---
  res="$(_hub_claude_edit "$claude" "$( (( remove )) && echo remove || echo add)" "$script" 0)"
  case "$res" in
    NO_PYTHON) say "  Claude: python3 not found — add these to $claude by hand:"
               printf '    "hooks": {\n      "SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"%s session"}]}],\n      "PreToolUse": [{"matcher":"Edit|Write|MultiEdit|NotebookEdit|Bash","hooks":[{"type":"command","command":"%s guard"}]}]\n    }\n' "$script" "$script" ;;
    BAD_JSON*) warn "  Claude: $claude is not valid JSON — left alone (${res#BAD_JSON })" ;;
    UNCHANGED) say "  Claude: $claude — already $( (( remove )) && echo 'clean' || echo 'installed'), nothing to do" ;;
    *) say "  Claude: $claude — $( (( remove )) && echo 'remove' || echo 'add') hub-route SessionStart + PreToolUse entries"
       if (( apply )); then bdir="$(_hub_backup "$claude")"; mkdir -p "$(dirname "$claude")"; _hub_claude_edit "$claude" "$( (( remove )) && echo remove || echo add)" "$script" 1 >/dev/null; ok "  Claude: written${bdir:+ (backup in $bdir)}"; fi ;;
  esac

  # --- Codex ---
  if (( remove )); then
    if [[ -f "$codex" ]] && grep -qF "$HUB_TOML_BEGIN" "$codex"; then
      say "  Codex:  $codex — remove the marked agentboard block"
      if (( apply )); then
        bdir="$(_hub_backup "$codex")"; tmp="$(mktemp)"
        awk -v b="$HUB_TOML_BEGIN" -v e="$HUB_TOML_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$codex" > "$tmp" && mv "$tmp" "$codex"
        ok "  Codex:  block removed (backup in $bdir)"
      fi
    else say "  Codex:  $codex — no agentboard block, nothing to do"; fi
  elif [[ -f "$codex" ]] && grep -qF "$HUB_TOML_BEGIN" "$codex"; then
    say "  Codex:  $codex — already installed, nothing to do"
  elif [[ -d "$HOME/.codex" ]]; then
    say "  Codex:  $codex — append this block:"; _hub_toml_block | sed 's/^/    /'
    if (( apply )); then
      bdir="$(_hub_backup "$codex")"; { [[ -s "$codex" ]] && printf '\n'; _hub_toml_block; } >> "$codex"
      ok "  Codex:  appended${bdir:+ (backup in $bdir)} — open Codex and trust the hooks once (/hooks)"
    fi
  else say "  Codex:  ~/.codex not found — skipped"; fi
  (( apply )) || { say; say "  Nothing was written. Re-run with --apply."; }
  return 0
}
