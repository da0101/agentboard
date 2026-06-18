#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

PLATFORM="$TEST_ROOT/templates/platform"
ROLES="$PLATFORM/roles"
SKILLS_TMPL="$TEST_ROOT/templates/skills"
EXT="$TEST_ROOT/extensions/vscode/src"

# 1. templates/platform/roles/code-simplifier.md exists
test_role_code_simplifier_exists() {
  [[ -f "$ROLES/code-simplifier.md" ]] || fail "templates/platform/roles/code-simplifier.md missing"
}

# 2. templates/platform/roles/build-error-resolver.md exists
test_role_build_error_resolver_exists() {
  [[ -f "$ROLES/build-error-resolver.md" ]] || fail "templates/platform/roles/build-error-resolver.md missing"
}

# 3. templates/platform/roles/a11y-engineer.md exists
test_role_a11y_engineer_exists() {
  [[ -f "$ROLES/a11y-engineer.md" ]] || fail "templates/platform/roles/a11y-engineer.md missing"
}

# 4. templates/platform/roles/database-reviewer.md exists
test_role_database_reviewer_exists() {
  [[ -f "$ROLES/database-reviewer.md" ]] || fail "templates/platform/roles/database-reviewer.md missing"
}

# 5. templates/platform/roles/api-engineer.md exists
test_role_api_engineer_exists() {
  [[ -f "$ROLES/api-engineer.md" ]] || fail "templates/platform/roles/api-engineer.md missing"
}

# 6. templates/platform/roles/ml-engineer.md exists
test_role_ml_engineer_exists() {
  [[ -f "$ROLES/ml-engineer.md" ]] || fail "templates/platform/roles/ml-engineer.md missing"
}

# 7. templates/platform/roles/harness-optimizer.md exists
test_role_harness_optimizer_exists() {
  [[ -f "$ROLES/harness-optimizer.md" ]] || fail "templates/platform/roles/harness-optimizer.md missing"
}

# 8. templates/platform/roles/docs-reviewer.md exists
test_role_docs_reviewer_exists() {
  [[ -f "$ROLES/docs-reviewer.md" ]] || fail "templates/platform/roles/docs-reviewer.md missing"
}

# 9. templates/skills/ab-gan/SKILL.md exists
test_skill_ab_gan_exists() {
  [[ -f "$SKILLS_TMPL/ab-gan/SKILL.md" ]] || fail "templates/skills/ab-gan/SKILL.md missing"
}

# 10. extensions/vscode/src/catalogProvider.ts exists
test_vscode_catalog_provider_exists() {
  [[ -f "$EXT/catalogProvider.ts" ]] || fail "extensions/vscode/src/catalogProvider.ts missing"
}

# 11. templates/platform/roles/INDEX.md contains "code-simplifier"
test_roles_index_contains_code_simplifier() {
  local index="$ROLES/INDEX.md"
  [[ -f "$index" ]] || fail "templates/platform/roles/INDEX.md missing"
  grep -q "code-simplifier" "$index" || fail "templates/platform/roles/INDEX.md does not contain 'code-simplifier'"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_role_code_simplifier_exists
test_role_build_error_resolver_exists
test_role_a11y_engineer_exists
test_role_database_reviewer_exists
test_role_api_engineer_exists
test_role_ml_engineer_exists
test_role_harness_optimizer_exists
test_role_docs_reviewer_exists
test_skill_ab_gan_exists
test_vscode_catalog_provider_exists
test_roles_index_contains_code_simplifier
