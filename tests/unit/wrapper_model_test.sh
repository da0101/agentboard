#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

test_codex_wrapper_has_model_selection() {
  local codex="$TEST_ROOT/templates/platform/scripts/codex-ab"
  grep -q "_ab_model" "$codex" \
    || fail "codex-ab does not define _ab_model"
  grep -q "\-\-model" "$codex" \
    || fail "codex-ab does not pass --model to codex"
}

test_gemini_wrapper_has_model_selection() {
  local gemini="$TEST_ROOT/templates/platform/scripts/gemini-ab"
  grep -q "_ab_model" "$gemini" \
    || fail "gemini-ab does not define _ab_model"
  grep -q "\-\-model" "$gemini" \
    || fail "gemini-ab does not pass --model to gemini"
}

test_codex_defaults_to_o4_mini_non_tty() {
  local codex="$TEST_ROOT/templates/platform/scripts/codex-ab"
  grep -q '_ab_model="o4-mini"' "$codex" \
    || fail "codex-ab does not default _ab_model to o4-mini"
}

test_gemini_defaults_to_flash_non_tty() {
  local gemini="$TEST_ROOT/templates/platform/scripts/gemini-ab"
  grep -q '_ab_model="gemini-2.5-flash"' "$gemini" \
    || fail "gemini-ab does not default _ab_model to gemini-2.5-flash"
}

test_sessionstart_includes_model_codex() {
  local codex="$TEST_ROOT/templates/platform/scripts/codex-ab"
  grep -q 'SessionStart' "$codex" \
    || fail "codex-ab does not emit SessionStart"
  grep 'SessionStart' "$codex" | grep -q 'model' \
    || fail "codex-ab SessionStart event does not include model"
}

test_sessionstart_includes_model_gemini() {
  local gemini="$TEST_ROOT/templates/platform/scripts/gemini-ab"
  grep -q 'SessionStart' "$gemini" \
    || fail "gemini-ab does not emit SessionStart"
  grep 'SessionStart' "$gemini" | grep -q 'model' \
    || fail "gemini-ab SessionStart event does not include model"
}

test_codex_wrapper_has_model_selection
test_gemini_wrapper_has_model_selection
test_codex_defaults_to_o4_mini_non_tty
test_gemini_defaults_to_flash_non_tty
test_sessionstart_includes_model_codex
test_sessionstart_includes_model_gemini
