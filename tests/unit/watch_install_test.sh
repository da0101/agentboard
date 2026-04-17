#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

_write_watch_stub_commands() {
  local bin_dir="$1"

  cat > "$bin_dir/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  print) [[ "${WATCH_TEST_LAUNCHCTL_PRINT:-0}" == "1" ]] ;;
  bootstrap) [[ "${WATCH_TEST_LAUNCHCTL_BOOTSTRAP_FAIL:-0}" == "1" ]] && exit 1 || exit 0 ;;
  load) [[ "${WATCH_TEST_LAUNCHCTL_LOAD_FAIL:-0}" == "1" ]] && exit 1 || exit 0 ;;
  bootout) [[ "${WATCH_TEST_LAUNCHCTL_BOOTOUT_FAIL:-1}" == "1" ]] && exit 1 || exit 0 ;;
  unload) exit 0 ;;
  *) exit 0 ;;
esac
EOF

  cat > "$bin_dir/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--user" ]]; then
  shift
fi

case "${1:-}" in
  daemon-reload) exit 0 ;;
  enable) [[ "${WATCH_TEST_SYSTEMCTL_ENABLE_FAIL:-0}" == "1" ]] && exit 1 || exit 0 ;;
  disable) [[ "${WATCH_TEST_SYSTEMCTL_DISABLE_FAIL:-0}" == "1" ]] && exit 1 || exit 0 ;;
  is-active) [[ "${WATCH_TEST_SYSTEMCTL_ACTIVE:-0}" == "1" ]] && exit 0 || exit 1 ;;
  *) exit 0 ;;
esac
EOF

  cat > "$bin_dir/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-u" ]]; then
  printf '%s\n' "${WATCH_TEST_UID:-501}"
  exit 0
fi

/usr/bin/id "$@"
EOF

  chmod +x "$bin_dir/launchctl" "$bin_dir/systemctl" "$bin_dir/id"
}

_run_watch_fn_capture() {
  local __resultvar="$1" dir="$2" fn="$3"
  shift 3

  local stub_bin script tmp captured status
  stub_bin="$(mktemp -d)"
  _write_watch_stub_commands "$stub_bin"
  script="$(mktemp)"

  cat > "$script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export PATH="$WATCH_STUB_BIN:$PATH"
source "$TEST_ROOT/bin/agentboard"

_watch_scheduler() {
  printf '%s\n' "${WATCH_TEST_SCHEDULER:-launchd}"
}

_watch_agentboard_bin() {
  if [[ "${WATCH_TEST_BIN_MODE:-ok}" == "missing" ]]; then
    die "Cannot resolve absolute path to agentboard binary"
  fi
  printf '%s' "${WATCH_TEST_BIN:-/tmp/agentboard-bin}"
}

cd "$WATCH_TEST_CWD"
fn="$1"
shift
"$fn" "$@"
EOF

  chmod +x "$script"
  tmp="$(mktemp)"

  set +e
  WATCH_STUB_BIN="$stub_bin" WATCH_TEST_CWD="$dir" TEST_ROOT="$TEST_ROOT" \
    "$script" "$fn" "$@" >"$tmp" 2>&1
  status=$?
  captured="$(cat "$tmp")"
  set -e

  rm -f "$script" "$tmp"
  rm -rf "$stub_bin"

  RUN_STATUS="$status"
  printf -v "$__resultvar" '%s' "$captured"
  return 0
}

_snapshot_tree() {
  local dir="$1"
  (
    cd "$dir"
    find . -print | sort
  )
}

_reset_watch_test_env() {
  unset AGENTBOARD_WATCH_HOME
  unset WATCH_TEST_SCHEDULER
  unset WATCH_TEST_BIN
  unset WATCH_TEST_BIN_MODE
  unset WATCH_TEST_LAUNCHCTL_PRINT
  unset WATCH_TEST_LAUNCHCTL_BOOTSTRAP_FAIL
  unset WATCH_TEST_LAUNCHCTL_LOAD_FAIL
  unset WATCH_TEST_LAUNCHCTL_BOOTOUT_FAIL
  unset WATCH_TEST_SYSTEMCTL_ENABLE_FAIL
  unset WATCH_TEST_SYSTEMCTL_DISABLE_FAIL
  unset WATCH_TEST_SYSTEMCTL_ACTIVE
  unset WATCH_TEST_UID
}

test_watch_install_slug_normalization() {
  local parent output dir
  _reset_watch_test_env
  parent="$(mktemp -d)"

  mkdir "$parent/My Project!"
  _run_watch_fn_capture output "$parent/My Project!" _watch_project_slug
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "my-project"

  mkdir "$parent/.foo"
  _run_watch_fn_capture output "$parent/.foo" _watch_project_slug
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "foo"

  _run_watch_fn_capture output "/tmp" _watch_project_slug
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" "tmp"

  _run_watch_fn_capture output "/" _watch_project_slug
  assert_status "$RUN_STATUS" 0
  assert_eq "$output" ""
}

test_watch_install_launchd_happy_path() {
  local dir home output plist slug
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  slug="$(printf '%s' "$(basename "$dir")" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  plist="$home/Library/LaunchAgents/com.agentboard.${slug}.plist"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  export WATCH_TEST_BIN="/opt/agentboard/bin/agentboard"
  export WATCH_TEST_LAUNCHCTL_PRINT="1"

  _run_watch_fn_capture output "$dir" _watch_install 2 3
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Installed launchd agent"
  [[ -f "$plist" ]] || fail "expected plist at $plist"
  assert_file_contains "$plist" "<string>/opt/agentboard/bin/agentboard</string>"
  assert_file_contains "$plist" "<key>WorkingDirectory</key>"
  assert_file_contains "$plist" "<string>$dir</string>"
  assert_file_contains "$plist" "<integer>120</integer>"
  assert_file_contains "$plist" "$home/.agentboard/watch-${slug}.log"
}

test_watch_install_systemd_happy_path() {
  local dir home output service timer slug
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  slug="$(printf '%s' "$(basename "$dir")" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  service="$home/.config/systemd/user/agentboard-${slug}.service"
  timer="$home/.config/systemd/user/agentboard-${slug}.timer"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="systemd"
  export WATCH_TEST_BIN="/opt/Agent Board/bin/agentboard"

  _run_watch_fn_capture output "$dir" _watch_install 7 4
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Installed systemd timer"
  [[ -f "$service" ]] || fail "expected service at $service"
  [[ -f "$timer" ]] || fail "expected timer at $timer"
  assert_file_contains "$service" "WorkingDirectory=$dir"
  assert_file_contains "$service" "ExecStart=\"/opt/Agent Board/bin/agentboard\" watch --once --quiet --threshold 4"
  assert_file_contains "$timer" "OnUnitActiveSec=7min"
}

test_watch_install_reinstall_is_idempotent() {
  local dir home output plist slug
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  slug="$(printf '%s' "$(basename "$dir")" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  plist="$home/Library/LaunchAgents/com.agentboard.${slug}.plist"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  export WATCH_TEST_BIN="/opt/agentboard/bin/agentboard"
  export WATCH_TEST_LAUNCHCTL_PRINT="1"

  _run_watch_fn_capture output "$dir" _watch_install 5 1
  assert_status "$RUN_STATUS" 0

  _run_watch_fn_capture output "$dir" _watch_install 20 1
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$plist" "<integer>1200</integer>"
  assert_file_not_contains "$plist" "<integer>300</integer>"
}

test_watch_uninstall_restores_temp_home() {
  local dir home before after output
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  export WATCH_TEST_BIN="/opt/agentboard/bin/agentboard"
  export WATCH_TEST_LAUNCHCTL_PRINT="1"

  before="$(_snapshot_tree "$home")"
  _run_watch_fn_capture output "$dir" _watch_install 10 1
  assert_status "$RUN_STATUS" 0

  _run_watch_fn_capture output "$dir" _watch_uninstall
  assert_status "$RUN_STATUS" 0
  after="$(_snapshot_tree "$home")"
  assert_eq "$after" "$before"
}

test_watch_uninstall_when_not_installed_is_noop() {
  local dir home output
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"

  _run_watch_fn_capture output "$dir" _watch_uninstall
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No launchd agent found"
}

test_watch_install_rejects_unsupported_scheduler() {
  local dir home output
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="unsupported"

  _run_watch_fn_capture output "$dir" _watch_install 10 1
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "only supported on macOS"
}

test_watch_install_rejects_empty_slug() {
  local parent dir home output
  _reset_watch_test_env
  parent="$(mktemp -d)"
  dir="$parent/!!!"
  mkdir "$dir"
  home="$(mktemp -d)"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"

  _run_watch_fn_capture output "$dir" _watch_install 10 1
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Could not derive a project slug"
}

test_watch_install_rejects_missing_bin() {
  local dir home output
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  export WATCH_TEST_BIN_MODE="missing"

  _run_watch_fn_capture output "$dir" _watch_install 10 1
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Cannot resolve absolute path to agentboard binary"
}

test_watch_status_distinguishes_states() {
  local dir home output plist slug
  _reset_watch_test_env
  dir="$(mktemp -d)"
  home="$(mktemp -d)"
  slug="$(printf '%s' "$(basename "$dir")" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  plist="$home/Library/LaunchAgents/com.agentboard.${slug}.plist"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  unset WATCH_TEST_LAUNCHCTL_PRINT

  _run_watch_fn_capture output "$dir" _watch_status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Installed: no — run: agentboard watch --install"

  mkdir -p "$(dirname "$plist")"
  printf '%s\n' '<plist />' > "$plist"
  _run_watch_fn_capture output "$dir" _watch_status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Installed: yes"
  assert_contains "$output" "Loaded: no"

  export WATCH_TEST_LAUNCHCTL_PRINT="1"
  _run_watch_fn_capture output "$dir" _watch_status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Loaded: yes"

  rm -f "$plist"
  _run_watch_fn_capture output "$dir" _watch_status
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "orphan"
}

test_watch_install_escapes_xml_paths() {
  local parent dir home output slug plist
  _reset_watch_test_env
  parent="$(mktemp -d)"
  dir="$parent/Proj<One>&Two"
  mkdir "$dir"
  home="$(mktemp -d)"
  slug="proj-one-two"
  plist="$home/Library/LaunchAgents/com.agentboard.${slug}.plist"

  export AGENTBOARD_WATCH_HOME="$home"
  export WATCH_TEST_SCHEDULER="launchd"
  export WATCH_TEST_BIN="/tmp/Agent&Board/bin/agentboard"
  export WATCH_TEST_LAUNCHCTL_PRINT="1"

  _run_watch_fn_capture output "$dir" _watch_install 10 1
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$plist" "Proj&lt;One&gt;&amp;Two"
  assert_file_contains "$plist" "/tmp/Agent&amp;Board/bin/agentboard"

  if command -v plutil >/dev/null 2>&1; then
    run_and_capture output plutil -lint "$plist"
    assert_status "$RUN_STATUS" 0
    assert_contains "$output" "OK"
  fi
}

for t in \
  test_watch_install_slug_normalization \
  test_watch_install_launchd_happy_path \
  test_watch_install_systemd_happy_path \
  test_watch_install_reinstall_is_idempotent \
  test_watch_uninstall_restores_temp_home \
  test_watch_uninstall_when_not_installed_is_noop \
  test_watch_install_rejects_unsupported_scheduler \
  test_watch_install_rejects_empty_slug \
  test_watch_install_rejects_missing_bin \
  test_watch_status_distinguishes_states \
  test_watch_install_escapes_xml_paths; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
