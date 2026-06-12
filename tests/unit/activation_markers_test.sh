#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

ACTIVATE_SINGLE="$TEST_ROOT/templates/platform/ACTIVATE.md"
ACTIVATE_HUB="$TEST_ROOT/templates/platform/ACTIVATE-HUB.md"

test_single_activation_documents_marker_contract() {
  [[ -f "$ACTIVATE_SINGLE" ]] || fail "$ACTIVATE_SINGLE missing"
  assert_file_contains "$ACTIVATE_SINGLE" "<!-- agentboard:root-entry:begin v=1 -->"
  assert_file_contains "$ACTIVATE_SINGLE" "<!-- agentboard:root-entry:end v=1 -->"
  assert_file_contains "$ACTIVATE_SINGLE" "Case C — Re-activation"
  assert_file_contains "$ACTIVATE_SINGLE" "Idempotency contract"
}

test_single_activation_step5_references_marker_contract() {
  [[ -f "$ACTIVATE_SINGLE" ]] || fail "$ACTIVATE_SINGLE missing"
  # Step 5 must reiterate the marker rule for AGENTS.md and GEMINI.md
  grep -q "same idempotency contract\|same marker" "$ACTIVATE_SINGLE" \
    || fail "ACTIVATE.md Step 5 does not reference the marker contract"
}

test_hub_activation_documents_marker_contract() {
  [[ -f "$ACTIVATE_HUB" ]] || fail "$ACTIVATE_HUB missing"
  assert_file_contains "$ACTIVATE_HUB" "<!-- agentboard:root-entry:begin v=1 -->"
  assert_file_contains "$ACTIVATE_HUB" "<!-- agentboard:root-entry:end v=1 -->"
  assert_file_contains "$ACTIVATE_HUB" "Case C — Re-activation"
}

test_activation_rules_list_includes_marker_invariant() {
  [[ -f "$ACTIVATE_SINGLE" ]] || fail "$ACTIVATE_SINGLE missing"
  [[ -f "$ACTIVATE_HUB" ]] || fail "$ACTIVATE_HUB missing"
  grep -q "MUST be wrapped in markers" "$ACTIVATE_SINGLE" \
    || fail "ACTIVATE.md activation rules do not encode the marker invariant"
  grep -q "MUST be wrapped in markers" "$ACTIVATE_HUB" \
    || fail "ACTIVATE-HUB.md activation rules do not encode the marker invariant"
}

test_step6_mandates_doctor_gate() {
  [[ -f "$ACTIVATE_SINGLE" ]] || fail "$ACTIVATE_SINGLE missing"
  [[ -f "$ACTIVATE_HUB" ]] || fail "$ACTIVATE_HUB missing"
  grep -q "ab doctor" "$ACTIVATE_SINGLE" \
    || fail "ACTIVATE.md Step 6 does not mandate running ab doctor"
  grep -q "errors > 0" "$ACTIVATE_SINGLE" \
    || fail "ACTIVATE.md Step 6 does not gate on doctor errors"
  grep -q "ab doctor" "$ACTIVATE_HUB" \
    || fail "ACTIVATE-HUB.md Step 6 does not mandate running ab doctor"
  grep -q "errors > 0" "$ACTIVATE_HUB" \
    || fail "ACTIVATE-HUB.md Step 6 does not gate on doctor errors"
}

test_single_activation_documents_marker_contract
test_single_activation_step5_references_marker_contract
test_hub_activation_documents_marker_contract
test_activation_rules_list_includes_marker_invariant
test_step6_mandates_doctor_gate
