#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

WORKFLOW="$TEST_ROOT/templates/platform/workflow.md"
AB_WORKFLOW="$TEST_ROOT/templates/skills/ab-workflow/SKILL.md"
AB_RESEARCH="$TEST_ROOT/templates/skills/ab-research/SKILL.md"
AB_TRIAGE="$TEST_ROOT/templates/skills/ab-triage/SKILL.md"
AB_QA="$TEST_ROOT/templates/skills/ab-qa/SKILL.md"

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
  assert_file_contains "$AB_TRIAGE" "research, worktree/local-environment prep, and human approval are mandatory"
}

test_workflow_requires_manual_qa_plan_when_human_verification_matters() {
  assert_file_contains "$WORKFLOW" "Manual QA plan — required when human verification matters"
  assert_file_contains "$WORKFLOW" "## 🧪 Manual QA Plan"
  assert_file_contains "$WORKFLOW" "Manual QA: not required"
  assert_file_contains "$WORKFLOW" "Bug repro / regression"
  assert_file_contains "$AB_WORKFLOW" "Manual QA Plan"
  assert_file_contains "$AB_WORKFLOW" "Manual QA: not required"
  assert_file_contains "$AB_QA" "tester-facing manual plan"
  assert_file_contains "$AB_QA" "Evidence to capture"
}

test_workflow_requires_worktree_branch_and_local_env_prep() {
  assert_file_contains "$WORKFLOW" "Worktree + local environment prep"
  assert_file_contains "$WORKFLOW" "feature/<stream-slug>"
  assert_file_contains "$WORKFLOW" "bugfix/<stream-slug>"
  assert_file_contains "$WORKFLOW" "hotfix/<stream-slug>"
  assert_file_contains "$WORKFLOW" "develop"
  assert_file_contains "$WORKFLOW" "master"
  assert_file_contains "$WORKFLOW" "Install development dependencies"
  assert_file_contains "$WORKFLOW" "localhost port"
  assert_file_contains "$AB_WORKFLOW" "Stage 1c — Worktree + local environment prep"
  assert_file_contains "$AB_WORKFLOW" "feature/<slug>"
  assert_file_contains "$AB_WORKFLOW" "bugfix/<slug>"
  assert_file_contains "$AB_WORKFLOW" "hotfix/<slug>"
  assert_file_contains "$AB_WORKFLOW" "localhost port"
  assert_file_contains "$AB_TRIAGE" "worktree/local-environment prep"
}

test_workflow_requires_research_first_new_stream_intake
test_skills_match_new_stream_research_and_approval_contract
test_workflow_requires_manual_qa_plan_when_human_verification_matters
test_workflow_requires_worktree_branch_and_local_env_prep
