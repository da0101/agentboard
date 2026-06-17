#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

PLATFORM="$TEST_ROOT/templates/platform"
SKILLS_TMPL="$TEST_ROOT/templates/skills"
SKILLS_RUNTIME="$TEST_ROOT/.claude/skills"
VSCODE="$TEST_ROOT/extensions/vscode"
NEW_SKILLS="ab-benchmark ab-browser-qa ab-architecture-audit ab-search-first ab-strategic-compact"

# 1. extensions/vscode/package.json exists and contains "agentboard"
test_vscode_package_json_exists_and_named_agentboard() {
  local pkg="$VSCODE/package.json"
  [[ -f "$pkg" ]] || fail "extensions/vscode/package.json missing"
  assert_file_contains "$pkg" "agentboard"
}

# 2. extensions/vscode/src/extension.ts exists
test_vscode_extension_ts_exists() {
  [[ -f "$VSCODE/src/extension.ts" ]] || fail "extensions/vscode/src/extension.ts missing"
}

# 3. extensions/vscode/src/hudProvider.ts exists
test_vscode_hud_provider_exists() {
  [[ -f "$VSCODE/src/hudProvider.ts" ]] || fail "extensions/vscode/src/hudProvider.ts missing"
}

# 4. extensions/vscode/src/streamsProvider.ts exists
test_vscode_streams_provider_exists() {
  [[ -f "$VSCODE/src/streamsProvider.ts" ]] || fail "extensions/vscode/src/streamsProvider.ts missing"
}

# 5. agentshield.sh hook exists and is under 80 lines
test_agentshield_hook_exists_and_under_80_lines() {
  local hook="$PLATFORM/scripts/hooks/agentshield.sh"
  [[ -f "$hook" ]] || fail "templates/platform/scripts/hooks/agentshield.sh missing"
  local lines
  lines="$(wc -l < "$hook")"
  [[ "$lines" -lt 80 ]] || fail "agentshield.sh is $lines lines (must be under 80)"
}

# 6. All 5 new skills exist in templates/skills/
test_new_skills_in_templates() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_TMPL/$slug" ]] || fail "templates/skills/$slug missing"
  done
}

# 7. All 5 new skills have runtime copies in .claude/skills/
test_new_skills_in_runtime() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_RUNTIME/$slug" ]] || fail ".claude/skills/$slug missing"
  done
}

# 8. templates/skills/ab-security/SKILL.md now exists
test_ab_security_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-security/SKILL.md" ]] || \
    fail "templates/skills/ab-security/SKILL.md missing"
}

# 9. lib/agentboard/commands/brief_patterns.sh exists
test_brief_patterns_sh_exists() {
  [[ -f "$TEST_ROOT/lib/agentboard/commands/brief_patterns.sh" ]] || \
    fail "lib/agentboard/commands/brief_patterns.sh missing"
}

# 10. brief.sh is still under 300 lines
test_brief_sh_under_300_lines() {
  local brief="$TEST_ROOT/lib/agentboard/commands/brief.sh"
  [[ -f "$brief" ]] || fail "lib/agentboard/commands/brief.sh missing"
  local lines
  lines="$(wc -l < "$brief")"
  [[ "$lines" -lt 300 ]] || fail "brief.sh is $lines lines (must be under 300)"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_vscode_package_json_exists_and_named_agentboard
test_vscode_extension_ts_exists
test_vscode_hud_provider_exists
test_vscode_streams_provider_exists
test_agentshield_hook_exists_and_under_80_lines
test_new_skills_in_templates
test_new_skills_in_runtime
test_ab_security_skill_md_exists
test_brief_patterns_sh_exists
test_brief_sh_under_300_lines
