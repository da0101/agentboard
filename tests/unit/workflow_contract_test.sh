#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

WORKFLOW="$TEST_ROOT/templates/platform/workflow.md"
AB_WORKFLOW="$TEST_ROOT/templates/skills/ab-workflow/SKILL.md"
AB_RESEARCH="$TEST_ROOT/templates/skills/ab-research/SKILL.md"
AB_TRIAGE="$TEST_ROOT/templates/skills/ab-triage/SKILL.md"

test_workflow_requires_research_first_new_stream_intake() {
  assert_file_contains "$WORKFLOW" "New stream intake contract"
  assert_file_contains "$WORKFLOW" "Research is always required for new streams"
  assert_file_contains "$WORKFLOW" "Human-in-the-loop is mandatory"
  assert_file_contains "$WORKFLOW" "wait for human validation/approval before implementation starts"
}

test_skills_match_new_stream_research_and_approval_contract() {
  assert_file_contains "$AB_WORKFLOW" "Stage 3 — Research (always for new streams"
  assert_file_contains "$AB_WORKFLOW" "Wait for user approval before implementing any new stream"
  assert_file_contains "$AB_RESEARCH" "Before proposing a plan for any new stream"
  assert_file_contains "$AB_RESEARCH" "For new streams, always run this"
  assert_file_contains "$AB_TRIAGE" "New-stream override"
  assert_file_contains "$AB_TRIAGE" "research and human approval are mandatory"
}

test_workflow_requires_research_first_new_stream_intake
test_skills_match_new_stream_research_and_approval_contract
