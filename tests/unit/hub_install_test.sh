#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# Fresh throwaway HOME with a Claude settings file that already has other things in it.
setup_home() {
  HI="$(mktemp -d)"; export HOME="$HI"; mkdir -p "$HI/.claude" "$HI/.codex" "$HI/proj"
  cat > "$HI/.claude/settings.json" <<'EOT'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mine"}]}
    ]
  }
}
EOT
  printf '[features]\nhooks = true\n\n[hooks.state."/x/.codex/config.toml:stop:0:0"]\ntrusted_hash = "abc"\n' > "$HI/.codex/config.toml"
  CL="$HI/.claude/settings.json"; CX="$HI/.codex/config.toml"
}

jq_py() { python3 -I -c "import json,sys; d=json.load(open('$CL')); $1"; }

test_preview_writes_nothing() {
  local output before_c before_x
  setup_home; before_c="$(cat "$CL")"; before_x="$(cat "$CX")"
  run_cli_capture output "$HI/proj" hub install
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "preview"; assert_contains "$output" "Nothing was written"
  assert_eq "$(cat "$CL")" "$before_c"; assert_eq "$(cat "$CX")" "$before_x"
  [[ ! -d "$HI/.agentboard/backups" ]] || fail "a preview must not create backups"
}

test_apply_adds_both_hooks_keeps_existing_settings_and_backs_up() {
  local output
  setup_home
  run_cli_capture output "$HI/proj" hub install --apply
  assert_status "$RUN_STATUS" 0
  jq_py "assert d['model']=='opus'"
  jq_py "assert any(h['command']=='echo mine' for g in d['hooks']['PreToolUse'] for h in g['hooks'])"
  jq_py "assert any('hub-route.sh session' in h['command'] for g in d['hooks']['SessionStart'] for h in g['hooks'])"
  jq_py "assert any('hub-route.sh guard' in h['command'] for g in d['hooks']['PreToolUse'] for h in g['hooks'])"
  assert_file_contains "$CX" "agentboard hub-route"; assert_file_contains "$CX" "hub-route.sh guard"
  assert_file_contains "$CX" 'trusted_hash = "abc"'          # existing Codex content untouched
  [[ -n "$(ls "$HI/.agentboard/backups"/settings.json.* 2>/dev/null)" ]] || fail "Claude backup missing"
  [[ -n "$(ls "$HI/.agentboard/backups"/config.toml.* 2>/dev/null)" ]] || fail "Codex backup missing"
}

test_install_is_idempotent() {
  local output c1 x1
  setup_home
  run_cli_capture output "$HI/proj" hub install --apply
  c1="$(cat "$CL")"; x1="$(cat "$CX")"
  run_cli_capture output "$HI/proj" hub install --apply
  assert_contains "$output" "already installed"
  assert_eq "$(cat "$CL")" "$c1"; assert_eq "$(cat "$CX")" "$x1"
}

test_uninstall_restores_the_original_exactly() {
  local output orig_x
  setup_home; orig_x="$(cat "$CX")"
  run_cli_capture output "$HI/proj" hub install --apply
  run_cli_capture output "$HI/proj" hub uninstall --apply
  assert_status "$RUN_STATUS" 0
  jq_py "assert d['model']=='opus'"
  jq_py "assert 'SessionStart' not in d['hooks']"
  jq_py "assert [h['command'] for g in d['hooks']['PreToolUse'] for h in g['hooks']]==['echo mine']"
  assert_file_not_contains "$CX" "hub-route"
  assert_eq "$(cat "$CX")" "$orig_x"
}

test_invalid_claude_json_is_left_alone() {
  local output
  setup_home; printf '{ this is not json' > "$CL"
  run_cli_capture output "$HI/proj" hub install --apply
  assert_contains "$output" "not valid JSON"
  assert_eq "$(cat "$CL")" "{ this is not json"
}

test_missing_files_are_created_or_skipped_sensibly() {
  local output
  setup_home; rm -f "$CL"; rm -rf "$HI/.codex"
  run_cli_capture output "$HI/proj" hub install --apply
  assert_status "$RUN_STATUS" 0
  [[ -f "$CL" ]] || fail "settings.json should be created"
  jq_py "assert d['hooks']['SessionStart']"
  assert_contains "$output" "skipped"; [[ ! -e "$HI/.codex" ]] || fail "must not invent ~/.codex"
}

test_codex_block_is_valid_toml_next_to_existing_hook_state() {
  setup_home
  run_cli_capture OUT "$HI/proj" hub install --apply
  if python3 -I -c 'import tomllib' 2>/dev/null; then
    python3 -I -c "import tomllib; d=tomllib.load(open('$CX','rb')); assert d['hooks']['SessionStart'][0]['hooks'][0]['type']=='command'; assert d['hooks']['PreToolUse'][0]['hooks'][0]['command'].endswith('guard'); assert 'state' in d['hooks']"
  fi
}

test_preview_writes_nothing
test_apply_adds_both_hooks_keeps_existing_settings_and_backs_up
test_install_is_idempotent
test_uninstall_restores_the_original_exactly
test_invalid_claude_json_is_left_alone
test_missing_files_are_created_or_skipped_sensibly
test_codex_block_is_valid_toml_next_to_existing_hook_state
