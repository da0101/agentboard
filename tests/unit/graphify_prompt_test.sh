#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Helper: create a temp bin dir with or without a fake graphify script
# ---------------------------------------------------------------------------
_fake_bin_with_graphify() {
  local tmpbin="$1"
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
mkdir -p graphify-out
printf "stub\n" > graphify-out/graph.json
exit 0
EOF
  chmod +x "$tmpbin/graphify"
}

_fake_bin_failing_graphify() {
  local tmpbin="$1"
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$tmpbin/graphify"
}

# ---------------------------------------------------------------------------
# test: graphify absent → tip printed, no prompt, exit 0
# ---------------------------------------------------------------------------
test_graphify_absent_prints_tip() {
  local output tmpbin
  tmpbin="$(mktemp -d)"
  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    _graphify_maybe_prompt "/tmp/fake-target"
  '
  assert_contains "$output" "uv tool install graphifyy"
  assert_not_contains "$output" "build a knowledge graph"
  rm -rf "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer N → no graphify run
# ---------------------------------------------------------------------------
test_graphify_present_answer_no() {
  local output tmpdir tmpbin
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
echo "ERROR: graphify should not have been called" >&2
exit 99
EOF
  chmod +x "$tmpbin/graphify"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    printf "N\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  assert_not_contains "$output" "Running graphify"
  assert_not_contains "$output" "should not have been called"
  rm -rf "$tmpdir" "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer Y, graphify succeeds → .platform/graphify/ created
# ---------------------------------------------------------------------------
test_graphify_present_answer_yes_success() {
  local tmpdir tmpbin output
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  mkdir -p "$tmpdir/.platform"
  _fake_bin_with_graphify "$tmpbin"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    cd "'"$tmpdir"'"
    printf "Y\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  [[ -d "$tmpdir/.platform/graphify" ]] \
    || fail "expected .platform/graphify/ to be created"
  [[ -f "$tmpdir/.platform/graphify/graph.json" ]] \
    || fail "expected graph.json inside .platform/graphify/"
  assert_contains "$output" "Knowledge graph"
  rm -rf "$tmpdir" "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer Y, graphify exits non-zero → warning, exit 0
# ---------------------------------------------------------------------------
test_graphify_present_answer_yes_failure() {
  local tmpdir tmpbin output
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  mkdir -p "$tmpdir/.platform"
  _fake_bin_failing_graphify "$tmpbin"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    cd "'"$tmpdir"'"
    printf "Y\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  assert_contains "$output" "Warning"
  assert_not_contains "$output" "Knowledge graph"
  rm -rf "$tmpdir" "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer Y, graphify exits 0 but no graphify-out/ → no ok line
# ---------------------------------------------------------------------------
test_graphify_present_answer_yes_no_output_dir() {
  local tmpdir tmpbin output
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  mkdir -p "$tmpdir/.platform"
  # Fake graphify that exits 0 but creates no graphify-out/
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpbin/graphify"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    cd "'"$tmpdir"'"
    printf "Y\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  assert_not_contains "$output" "Knowledge graph"
  assert_contains "$output" "skipped"
  rm -rf "$tmpdir" "$tmpbin"
}

test_graphify_absent_prints_tip
test_graphify_present_answer_no
test_graphify_present_answer_yes_success
test_graphify_present_answer_yes_failure
test_graphify_present_answer_yes_no_output_dir
