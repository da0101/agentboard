#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

CI_WORKFLOW="$TEST_ROOT/.github/workflows/ci.yml"
STREAM_WORKFLOW="$TEST_ROOT/.github/workflows/stream-status.yml"
DOCTOR="$TEST_ROOT/lib/agentboard/commands/doctor.sh"
VALIDATE="$TEST_ROOT/lib/agentboard/commands/validate.sh"

# 1. .github/workflows/ci.yml contains "agentboard-validate" job
test_ci_yml_has_agentboard_validate_job() {
  [[ -f "$CI_WORKFLOW" ]] || fail ".github/workflows/ci.yml missing"
  assert_file_contains "$CI_WORKFLOW" "agentboard-validate"
}

# 2. .github/workflows/ci.yml contains "bash tests/unit.sh"
test_ci_yml_runs_unit_tests() {
  [[ -f "$CI_WORKFLOW" ]] || fail ".github/workflows/ci.yml missing"
  assert_file_contains "$CI_WORKFLOW" "bash tests/unit.sh"
}

# 3. lib/agentboard/commands/doctor.sh contains "--ci"
test_doctor_has_ci_flag() {
  [[ -f "$DOCTOR" ]] || fail "lib/agentboard/commands/doctor.sh missing"
  assert_file_contains "$DOCTOR" "--ci"
}

# 4. lib/agentboard/commands/validate.sh contains "--ci"
test_validate_has_ci_flag() {
  [[ -f "$VALIDATE" ]] || fail "lib/agentboard/commands/validate.sh missing"
  assert_file_contains "$VALIDATE" "--ci"
}

# 5. validate.sh contains "::error file=" (GitHub Actions annotation format)
test_validate_emits_gha_annotations() {
  [[ -f "$VALIDATE" ]] || fail "lib/agentboard/commands/validate.sh missing"
  assert_file_contains "$VALIDATE" "::error file="
}

# 6. .github/workflows/stream-status.yml exists
test_stream_status_workflow_exists() {
  [[ -f "$STREAM_WORKFLOW" ]] || fail ".github/workflows/stream-status.yml missing"
}

# 7. stream-status.yml contains "pull_request"
test_stream_status_triggers_on_pull_request() {
  [[ -f "$STREAM_WORKFLOW" ]] || fail ".github/workflows/stream-status.yml missing"
  assert_file_contains "$STREAM_WORKFLOW" "pull_request"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_ci_yml_has_agentboard_validate_job
test_ci_yml_runs_unit_tests
test_doctor_has_ci_flag
test_validate_has_ci_flag
test_validate_emits_gha_annotations
test_stream_status_workflow_exists
test_stream_status_triggers_on_pull_request
