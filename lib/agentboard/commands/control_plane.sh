# -----------------------------------------------------------------------------
# control_plane.sh — wraps the Node.js control plane for the agentboard CLI
# -----------------------------------------------------------------------------

_cp_bin()      { echo "$AGENTBOARD_ROOT/lib/node/control-plane.js"; }
_cp_pid_file() { echo "$HOME/.agentboard/control-plane.pid"; }
_cp_is_running() { [[ -f "$(_cp_pid_file)" ]] && kill -0 "$(cat "$(_cp_pid_file)")" 2>/dev/null; }
_cp_url()      { echo "http://127.0.0.1:${AGENTBOARD_PORT:-7842}"; }

cmd_cp_start() {
  _cp_is_running && { ok "Control plane already running (PID $(cat "$(_cp_pid_file)"))"; return 0; }
  command -v node >/dev/null 2>&1 || die "node is required for the control plane. Install Node.js >= 16."
  mkdir -p "$HOME/.agentboard"
  nohup node "$(_cp_bin)" > "$HOME/.agentboard/control-plane.log" 2>&1 &
  echo $! > "$(_cp_pid_file)"
  sleep 0.5
  _cp_is_running \
    && ok "Control plane started (PID $!)" \
    || die "Control plane failed to start. Check $HOME/.agentboard/control-plane.log"
}

cmd_cp_stop() {
  _cp_is_running || { say "Control plane not running."; return 0; }
  kill "$(cat "$(_cp_pid_file)")" 2>/dev/null || true
  rm -f "$(_cp_pid_file)"
  ok "Control plane stopped."
}

cmd_cp_status() {
  if _cp_is_running; then
    local resp; resp="$(curl -sf -m 2 "$(_cp_url)/status" 2>/dev/null || echo "{}")"
    ok "Control plane running (PID $(cat "$(_cp_pid_file)"))"
    printf "%s\n" "$resp"
  else
    say "Control plane not running. Run: ab start"
  fi
}

cmd_sessions() {
  _cp_is_running || die "Control plane not running. Run: ab start"
  curl -sf -m 3 "$(_cp_url)/sessions" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
rows = d.get('sessions', [])
if not rows:
  print('  (no sessions)')
  exit()
print(f'  {len(rows)} session(s):')
for r in rows:
  print(f'  [{r.get(\"status\",\"?\")}] {r.get(\"role\",\"?\")} / {r.get(\"stream_slug\",\"?\")} — {r.get(\"started_at\",\"\")[:16]}')
"
}

cmd_delegate() {
  local task="${*}"
  [[ -n "$task" ]] || die "Usage: ab delegate <task description>"
  _cp_is_running || die "Control plane not running. Run: ab start"
  local payload; payload="{\"task\":$(printf "%s" "$task" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")"
  local stream_slug; stream_slug="$(frontmatter_value "$(ls .platform/work/*.md 2>/dev/null | head -1)" "slug" 2>/dev/null || true)"
  [[ -n "$stream_slug" ]] && payload="${payload},\"stream_slug\":\"${stream_slug}\""
  payload="${payload}}"
  curl -sf -m 5 -X POST -H "Content-Type: application/json" -d "$payload" "$(_cp_url)/delegate" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Role: {d[\"role\"][\"name\"]} [{d[\"role\"][\"slug\"]}] (model: {d[\"role\"][\"model\"]})')
print(f'Worktree recommended: {d[\"suggest_worktree\"]}')
print('\n--- Delegation prompt ---')
print(d['prompt'])
"
}

cmd_worktree() {
  local sub="${1:-list}"; shift 2>/dev/null || true
  case "$sub" in
    list)
      if _cp_is_running; then
        curl -sf -m 3 "$(_cp_url)/worktrees" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for w in d.get('worktrees', []):
  label = 'main' if w['isMain'] else 'worktree'
  print(f'  [{label}] {w[\"branch\"]} → {w[\"path\"]}')
"
      else
        git worktree list 2>/dev/null || say "No worktrees found."
      fi
      ;;
    new)
      local slug="${1:?Usage: ab worktree new <stream-slug>}"
      _cp_is_running || die "Control plane not running. Run: ab start"
      curl -sf -m 10 -X POST -H "Content-Type: application/json" \
        -d "{\"stream_slug\":\"${slug}\"}" "$(_cp_url)/worktrees" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Created: {d[\"path\"]} ({d[\"branch\"]})')
"
      ;;
    *) die "Usage: ab worktree list|new <slug>" ;;
  esac
}
