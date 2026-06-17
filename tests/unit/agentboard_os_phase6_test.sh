#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

SKILLS_TMPL="$TEST_ROOT/templates/skills"
SKILLS_RUNTIME="$TEST_ROOT/.claude/skills"

NEW_SKILLS="ab-adr ab-agent-introspection ab-agent-harness ab-skill-comply ab-scientific-thinking ab-taste ab-article-writing"

# 1-7. New skills exist in templates/skills/
test_new_skills_in_templates() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -f "$SKILLS_TMPL/$slug/SKILL.md" ]] || fail "templates/skills/$slug/SKILL.md missing"
  done
}

# 8. All 7 new skills have a runtime copy in .claude/skills/
test_new_skills_in_runtime() {
  local slug
  for slug in $NEW_SKILLS; do
    [[ -d "$SKILLS_RUNTIME/$slug" ]] || fail ".claude/skills/$slug missing"
  done
}

# 9. Total skill count in templates/skills/ is at least 36
test_total_skill_count_at_least_36() {
  local count
  count="$(ls -d "$SKILLS_TMPL"/ab-* 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$count" -ge 36 ]] || fail "Expected at least 36 skills in templates/skills/, found $count"
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------
test_new_skills_in_templates
test_new_skills_in_runtime
test_total_skill_count_at_least_36
