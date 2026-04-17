#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

CLAUDE_TMPL="$TEST_ROOT/templates/root/CLAUDE.md.template"
AGENTS_TMPL="$TEST_ROOT/templates/root/AGENTS.md.template"
GEMINI_TMPL="$TEST_ROOT/templates/root/GEMINI.md.template"

test_all_entry_templates_reference_handoff_on_session_start() {
  for t in "$CLAUDE_TMPL" "$AGENTS_TMPL" "$GEMINI_TMPL"; do
    [[ -f "$t" ]] || fail "$t missing"
    assert_file_contains "$t" "agentboard handoff <slug>"
  done
}

test_all_entry_templates_reference_checkpoint_before_handoff() {
  for t in "$CLAUDE_TMPL" "$AGENTS_TMPL" "$GEMINI_TMPL"; do
    [[ -f "$t" ]] || fail "$t missing"
    assert_file_contains "$t" "agentboard checkpoint"
    assert_file_contains "$t" "--what"
    assert_file_contains "$t" "--next"
  done
}

test_all_entry_templates_reference_resume_state() {
  for t in "$CLAUDE_TMPL" "$AGENTS_TMPL" "$GEMINI_TMPL"; do
    [[ -f "$t" ]] || fail "$t missing"
    assert_file_contains "$t" "Resume state"
  done
}

test_all_entry_templates_reference_handoff_on_session_start
test_all_entry_templates_reference_checkpoint_before_handoff
test_all_entry_templates_reference_resume_state
