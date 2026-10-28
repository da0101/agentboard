#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

CLAUDE_TMPL="$TEST_ROOT/templates/root/CLAUDE.md.template"
AGENTS_TMPL="$TEST_ROOT/templates/root/AGENTS.md.template"
GEMINI_TMPL="$TEST_ROOT/templates/root/GEMINI.md.template"
CLAUDE_LIVE="$TEST_ROOT/CLAUDE.md"
AGENTS_LIVE="$TEST_ROOT/AGENTS.md"
GEMINI_LIVE="$TEST_ROOT/GEMINI.md"
HUB_TMPL="$TEST_ROOT/templates/root/CLAUDE.md.hub.template"
PROTO="$TEST_ROOT/templates/platform/protocols"
KERNEL_CORE="$TEST_ROOT/templates/platform/kernel/core.md"

# The stubs no longer carry the procedures. They carry the generated kernel
# (hard rules + `ab protocol` triggers); the long text lives in protocols/.

test_entry_templates_carry_the_generated_kernel_and_it_is_fresh() {
  local t provider want got
  for t in "$CLAUDE_TMPL" "$AGENTS_TMPL" "$GEMINI_TMPL" "$HUB_TMPL"; do
    [[ -f "$t" ]] || fail "$t missing"
    case "$(basename "$t")" in AGENTS*) provider=codex ;; GEMINI*) provider=gemini ;; *) provider=claude ;; esac
    want="$("$TEST_ROOT/bin/ab" entry kernel "$provider")"
    got="$(awk '/agentboard:kernel:begin/{f=1} f{print} /agentboard:kernel:end/{f=0}' "$t")"
    [[ "$got" == "$want" ]] || fail "$(basename "$t") kernel is stale — run: ab entry build-templates"
  done
}

test_kernel_covers_session_start_checkpoint_and_handoff() {
  assert_file_contains "$KERNEL_CORE" "ab brief --start"
  assert_file_contains "$KERNEL_CORE" "ab handoff <slug>"
  assert_file_contains "$KERNEL_CORE" "ab checkpoint <slug>"
  assert_file_contains "$KERNEL_CORE" "--what"
  assert_file_contains "$KERNEL_CORE" "--next"
}

test_kernel_points_at_every_protocol() {
  local p
  for p in new-task closure qa handoff reasoning roles audit; do
    assert_file_contains "$KERNEL_CORE" "ab protocol $p"
    [[ -f "$PROTO/$p.md" ]] || fail "protocol $p.md missing"
  done
}

test_kernel_states_the_branch_and_worktree_rule() {
  assert_file_contains "$KERNEL_CORE" "feature/<slug>"
  assert_file_contains "$KERNEL_CORE" "bugfix/<slug>"
  assert_file_contains "$KERNEL_CORE" "hotfix/<slug>"
  assert_file_contains "$KERNEL_CORE" "Worktrees are on demand"
  assert_file_contains "$KERNEL_CORE" "ab worktree new"
}

test_protocols_hold_the_detailed_rules() {
  assert_file_contains "$PROTO/handoff.md" "Resume state"
  assert_file_contains "$PROTO/new-task.md" "Research-first new stream rule"
  assert_file_contains "$PROTO/new-task.md" "targeted external research every time"
  assert_file_contains "$PROTO/new-task.md" "wait for human validation/approval before implementation"
  assert_file_contains "$PROTO/new-task.md" "Worktree branch rule"
  assert_file_contains "$PROTO/new-task.md" "Do not create a worktree by default"
  assert_file_contains "$PROTO/new-task.md" "development dependencies"
  assert_file_contains "$PROTO/new-task.md" "localhost port"
  assert_file_contains "$PROTO/qa.md" "Manual QA artifact rule"
  assert_file_contains "$PROTO/qa.md" ".platform/work/qa/<stream-slug>-manual-qa.md"
  assert_file_contains "$PROTO/qa.md" "commit, push, merge, release, or stream closure"
  assert_file_contains "$PROTO/qa.md" "bug repro/regression steps"
  assert_file_contains "$PROTO/qa.md" "Manual QA: not required"
  assert_file_contains "$PROTO/qa.md" "~/.agentboard/cold/"
  assert_file_contains "$PROTO/qa.md" "QA execution journal rule"
  assert_file_contains "$PROTO/qa.md" ".platform/work/qa/<stream-slug>-execution-journal.md"
  assert_file_contains "$PROTO/qa.md" "the journal is the chronological trace"
}

test_entry_stubs_stay_slim() {
  local t size
  for t in "$CLAUDE_TMPL" "$AGENTS_TMPL" "$GEMINI_TMPL"; do
    size="$(wc -c < "$t" | tr -d ' ')"
    (( size < 4500 )) || fail "$(basename "$t") is $size bytes; stubs must stay under 4500 (procedures belong in protocols/)"
  done
}

# This repo dogfoods the same layout: project block + generated kernel. The rules
# themselves are tested above (kernel + protocols); here we guard the dogfood.
test_live_entry_files_carry_the_kernel_and_stay_lean() {
  local t provider want got size
  for t in "$CLAUDE_LIVE" "$AGENTS_LIVE" "$GEMINI_LIVE"; do
    [[ -f "$t" ]] || fail "$t missing"
    case "$(basename "$t")" in AGENTS*) provider=codex ;; GEMINI*) provider=gemini ;; *) provider=claude ;; esac
    want="$("$TEST_ROOT/bin/ab" entry kernel "$provider")"
    got="$(awk '/agentboard:kernel:begin/{f=1} f{print} /agentboard:kernel:end/{f=0}' "$t")"
    [[ "$got" == "$want" ]] || fail "$(basename "$t") kernel is stale — run: ab entry sync"
    assert_file_contains "$t" "agentboard:root-entry:begin"
    size="$(wc -c < "$t" | tr -d ' ')"
    (( size < 8500 )) || fail "$(basename "$t") is $size bytes; keep the dogfood entry files lean (< 8500)"
  done
}

test_entry_templates_carry_the_generated_kernel_and_it_is_fresh
test_kernel_covers_session_start_checkpoint_and_handoff
test_kernel_points_at_every_protocol
test_kernel_states_the_branch_and_worktree_rule
test_protocols_hold_the_detailed_rules
test_entry_stubs_stay_slim
test_live_entry_files_carry_the_kernel_and_stay_lean
