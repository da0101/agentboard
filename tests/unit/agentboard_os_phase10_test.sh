#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

BIN="$TEST_ROOT/bin/ab"

test_control_plane_js_exists() {
  [[ -f "$TEST_ROOT/lib/node/control-plane.js" ]] || fail "lib/node/control-plane.js missing"
}

test_session_store_js_exists() {
  [[ -f "$TEST_ROOT/lib/node/session-store.js" ]] || fail "lib/node/session-store.js missing"
}

test_hud_writer_js_exists() {
  [[ -f "$TEST_ROOT/lib/node/hud-writer.js" ]] || fail "lib/node/hud-writer.js missing"
}

test_worktree_manager_js_exists() {
  [[ -f "$TEST_ROOT/lib/node/worktree-manager.js" ]] || fail "lib/node/worktree-manager.js missing"
}

test_delegation_router_js_exists() {
  [[ -f "$TEST_ROOT/lib/node/delegation-router.js" ]] || fail "lib/node/delegation-router.js missing"
}

test_control_plane_sh_exists() {
  [[ -f "$TEST_ROOT/lib/agentboard/commands/control_plane.sh" ]] || \
    fail "lib/agentboard/commands/control_plane.sh missing"
}

test_control_plane_sh_has_cmd_cp_start() {
  local f="$TEST_ROOT/lib/agentboard/commands/control_plane.sh"
  [[ -f "$f" ]] || fail "lib/agentboard/commands/control_plane.sh missing"
  grep -q "cmd_cp_start" "$f" || fail "control_plane.sh does not define cmd_cp_start"
}

test_sessions_provider_ts_exists() {
  [[ -f "$TEST_ROOT/extensions/vscode/src/sessionsProvider.ts" ]] || \
    fail "extensions/vscode/src/sessionsProvider.ts missing"
}

test_worktrees_provider_ts_exists() {
  [[ -f "$TEST_ROOT/extensions/vscode/src/worktreesProvider.ts" ]] || \
    fail "extensions/vscode/src/worktreesProvider.ts missing"
}

test_bin_ab_has_start_dispatch() {
  grep -q "start)" "$BIN" || fail "bin/ab does not contain 'start)' in dispatch table"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_control_plane_js_exists
test_session_store_js_exists
test_hud_writer_js_exists
test_worktree_manager_js_exists
test_delegation_router_js_exists
test_control_plane_sh_exists
test_control_plane_sh_has_cmd_cp_start
test_sessions_provider_ts_exists
test_worktrees_provider_ts_exists
test_bin_ab_has_start_dispatch
