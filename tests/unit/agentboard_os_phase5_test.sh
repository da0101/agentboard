#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

SKILLS_TMPL="$TEST_ROOT/templates/skills"
SKILLS_RUNTIME="$TEST_ROOT/.claude/skills"
NEW_SKILLS="ab-code-tour ab-api-design ab-agentic-engineering ab-autonomous-loop ab-blueprint ab-team-orchestration"

# 1. templates/skills/ab-code-tour/SKILL.md exists
test_ab_code_tour_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-code-tour/SKILL.md" ]] || \
    fail "templates/skills/ab-code-tour/SKILL.md missing"
}

# 2. templates/skills/ab-api-design/SKILL.md exists
test_ab_api_design_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-api-design/SKILL.md" ]] || \
    fail "templates/skills/ab-api-design/SKILL.md missing"
}

# 3. templates/skills/ab-agentic-engineering/SKILL.md exists
test_ab_agentic_engineering_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-agentic-engineering/SKILL.md" ]] || \
    fail "templates/skills/ab-agentic-engineering/SKILL.md missing"
}

# 4. templates/skills/ab-autonomous-loop/SKILL.md exists
test_ab_autonomous_loop_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-autonomous-loop/SKILL.md" ]] || \
    fail "templates/skills/ab-autonomous-loop/SKILL.md missing"
}

# 5. templates/skills/ab-blueprint/SKILL.md exists
test_ab_blueprint_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-blueprint/SKILL.md" ]] || \
    fail "templates/skills/ab-blueprint/SKILL.md missing"
}

# 6. templates/skills/ab-team-orchestration/SKILL.md exists
test_ab_team_orchestration_skill_md_exists() {
  [[ -f "$SKILLS_TMPL/ab-team-orchestration/SKILL.md" ]] || \
    fail "templates/skills/ab-team-orchestration/SKILL.md missing"
}

# 7. All 6 new skills have runtime copies in .claude/skills/
test_new_skills_in_runtime() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_RUNTIME/$slug" ]] || fail ".claude/skills/$slug missing"
  done
}

# 8. templates/skills/ab-skill-scout/SKILL.md contains "Self-Improvement Loop"
test_skill_scout_template_contains_self_improvement_loop() {
  local skill="$SKILLS_TMPL/ab-skill-scout/SKILL.md"
  [[ -f "$skill" ]] || fail "templates/skills/ab-skill-scout/SKILL.md missing"
  grep -q "Self-Improvement Loop" "$skill" || \
    fail "templates/skills/ab-skill-scout/SKILL.md does not contain 'Self-Improvement Loop'"
}

# 9. .claude/skills/ab-skill-scout/SKILL.md contains "Self-Improvement Loop"
test_skill_scout_runtime_contains_self_improvement_loop() {
  local skill="$SKILLS_RUNTIME/ab-skill-scout/SKILL.md"
  [[ -f "$skill" ]] || fail ".claude/skills/ab-skill-scout/SKILL.md missing"
  grep -q "Self-Improvement Loop" "$skill" || \
    fail ".claude/skills/ab-skill-scout/SKILL.md does not contain 'Self-Improvement Loop'"
}

# 10. Total skill count in templates/skills/ is at least 24
test_total_skill_count_at_least_24() {
  local count
  count="$(ls -d "$SKILLS_TMPL"/ab-* 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$count" -ge 24 ]] || \
    fail "templates/skills/ has only $count ab-* skills (expected at least 24)"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_ab_code_tour_skill_md_exists
test_ab_api_design_skill_md_exists
test_ab_agentic_engineering_skill_md_exists
test_ab_autonomous_loop_skill_md_exists
test_ab_blueprint_skill_md_exists
test_ab_team_orchestration_skill_md_exists
test_new_skills_in_runtime
test_skill_scout_template_contains_self_improvement_loop
test_skill_scout_runtime_contains_self_improvement_loop
test_total_skill_count_at_least_24
