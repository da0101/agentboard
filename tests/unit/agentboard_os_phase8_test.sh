#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

BIN="$TEST_ROOT/bin/agentboard"
SKILL_ADD="$TEST_ROOT/lib/agentboard/commands/skill_add.sh"
SCHEMA="$TEST_ROOT/templates/platform/schemas/skill-registry.json"

# 1. lib/agentboard/commands/skill_add.sh exists
test_skill_add_file_exists() {
  [[ -f "$SKILL_ADD" ]] || fail "lib/agentboard/commands/skill_add.sh missing"
}

# 2. skill_add.sh contains cmd_skill_add function
test_skill_add_function_defined() {
  assert_file_contains "$SKILL_ADD" "cmd_skill_add"
}

# 3. bin/agentboard contains "skill)" in its case statement
test_skill_command_registered_in_bin() {
  grep -q "skill)" "$BIN" || fail "bin/agentboard does not register 'skill)' command"
}

# 4. templates/platform/schemas/skill-registry.json exists
test_skill_registry_schema_exists() {
  [[ -f "$SCHEMA" ]] || fail "templates/platform/schemas/skill-registry.json missing"
}

# 5. skill-registry.json contains "agentboard" (origin field)
test_skill_registry_contains_origin() {
  assert_file_contains "$SCHEMA" "agentboard"
}

# 6. CONTRIBUTING-SKILLS.md exists at repo root
test_contributing_skills_doc_exists() {
  [[ -f "$TEST_ROOT/CONTRIBUTING-SKILLS.md" ]] || fail "CONTRIBUTING-SKILLS.md missing at repo root"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_skill_add_file_exists
test_skill_add_function_defined
test_skill_command_registered_in_bin
test_skill_registry_schema_exists
test_skill_registry_contains_origin
test_contributing_skills_doc_exists
