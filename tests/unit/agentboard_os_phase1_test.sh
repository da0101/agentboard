#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

PLATFORM="$TEST_ROOT/templates/platform"
SKILLS_TMPL="$TEST_ROOT/templates/skills"
SKILLS_RUNTIME="$TEST_ROOT/.claude/skills"
BIN="$TEST_ROOT/bin/agentboard"
NEW_SKILLS="ab-verification-loop ab-agent-eval ab-skill-scout ab-codebase-onboarding ab-tdd ab-canary ab-token-budget"

# 1. SOUL.md and RULES.md in templates/platform/
test_soul_and_rules_exist() {
  [[ -f "$PLATFORM/SOUL.md" ]]  || fail "templates/platform/SOUL.md missing"
  [[ -f "$PLATFORM/RULES.md" ]] || fail "templates/platform/RULES.md missing"
}

# 2. HUD schema file exists and contains all required top-level property keys
test_hud_schema_exists_and_has_required_keys() {
  local schema="$PLATFORM/schemas/agentboard.hud-status.v1.json"
  [[ -f "$schema" ]] || fail "templates/platform/schemas/agentboard.hud-status.v1.json missing"
  for key in context tool_calls active_agents todos checks cost risk queue; do
    grep -q "\"$key\"" "$schema" || fail "HUD schema missing required key: $key"
  done
}

# 3. All 7 new skills exist in templates/skills/
test_new_skills_in_templates() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_TMPL/$slug" ]] || fail "templates/skills/$slug missing"
  done
}

# 4. All 7 new skills have a runtime copy in .claude/skills/
test_new_skills_in_runtime() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_RUNTIME/$slug" ]] || fail ".claude/skills/$slug missing"
  done
}

# 5. All 4 new harness dirs have at least one file
test_harness_dirs_have_files() {
  [[ -f "$TEST_ROOT/.cursor/rules/agentboard.mdc" ]]    || fail ".cursor/rules/agentboard.mdc missing"
  [[ -f "$TEST_ROOT/.zed/settings.json" ]]               || fail ".zed/settings.json missing"
  [[ -f "$TEST_ROOT/.kiro/steering/agentboard.md" ]]     || fail ".kiro/steering/agentboard.md missing"
  [[ -f "$TEST_ROOT/.opencode/config.json" ]]            || fail ".opencode/config.json missing"
}

# 6. memory-persist.sh hook exists in templates/platform/scripts/hooks/
test_memory_persist_hook_exists() {
  [[ -f "$PLATFORM/scripts/hooks/memory-persist.sh" ]] || \
    fail "templates/platform/scripts/hooks/memory-persist.sh missing"
}

# 7. package.json at repo root with "name": "agentboard"
test_package_json_exists_and_named_agentboard() {
  local pkg="$TEST_ROOT/package.json"
  [[ -f "$pkg" ]] || fail "package.json missing at repo root"
  assert_file_contains "$pkg" '"name"'
  assert_file_contains "$pkg" '"agentboard"'
}

# 8. bin/agentboard-npm exists
test_agentboard_npm_bin_exists() {
  [[ -f "$TEST_ROOT/bin/agentboard-npm" ]] || fail "bin/agentboard-npm missing"
}

# 9. ab validate command is registered in bin/agentboard
test_validate_command_registered() {
  grep -q "validate)" "$BIN" || fail "bin/agentboard does not register 'validate)' command"
}

# 10. sync_skills.sh exists in lib/agentboard/commands/
test_sync_skills_command_exists() {
  [[ -f "$TEST_ROOT/lib/agentboard/commands/sync_skills.sh" ]] || \
    fail "lib/agentboard/commands/sync_skills.sh missing"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_soul_and_rules_exist
test_hud_schema_exists_and_has_required_keys
test_new_skills_in_templates
test_new_skills_in_runtime
test_harness_dirs_have_files
test_memory_persist_hook_exists
test_package_json_exists_and_named_agentboard
test_agentboard_npm_bin_exists
test_validate_command_registered
test_sync_skills_command_exists
