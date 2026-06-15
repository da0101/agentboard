#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

test_qa_self_heal_skill_exists_in_all_installed_locations() {
  local file
  for file in \
    "$TEST_ROOT/templates/skills/ab-qa-self-heal/SKILL.md" \
    "$TEST_ROOT/.claude/skills/ab-qa-self-heal/SKILL.md" \
    "$TEST_ROOT/.agents/skills/ab-qa-self-heal/SKILL.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Maestro"
    assert_file_contains "$file" "MCP"
    assert_file_contains "$file" "bounded"
    assert_file_contains "$file" "report"
    assert_file_contains "$file" "Do not stress production"
    assert_file_contains "$file" "explicit caps and approval"
    assert_file_contains "$file" "## Manual QA Artifact"
    assert_file_contains "$file" ".platform/work/qa/<stream-slug>-manual-qa.md"
    assert_file_contains "$file" "human tester or Maestro agent"
    assert_file_contains "$file" "## QA Execution Journal"
    assert_file_contains "$file" ".platform/work/qa/<stream-slug>-execution-journal.md"
    assert_file_contains "$file" "Maintain a chronological QA Execution Journal"
    assert_file_contains "$file" "Successful paths"
  done
}

test_qa_self_heal_role_routes_to_bounded_automation() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/roles/qa-automation-engineer.md" \
    "$TEST_ROOT/.platform/roles/qa-automation-engineer.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Maestro MCP/CLI"
    assert_file_contains "$file" "Self-heal narrowly"
    assert_file_contains "$file" "Bound the loop"
    assert_file_contains "$file" "Production or third-party stress needs explicit"
    assert_file_contains "$file" "QA Execution Journal"
    assert_file_contains "$file" ".platform/work/qa/<stream-slug>-execution-journal.md"
    assert_file_contains "$file" "No invisible app-driving"
  done
}

test_role_index_routes_qa_automation_to_self_heal_skill() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/roles/INDEX.md" \
    "$TEST_ROOT/.platform/roles/INDEX.md"
  do
    assert_file_contains "$file" 'qa-automation-engineer'
    assert_file_contains "$file" 'ab-qa-self-heal'
    assert_file_contains "$file" 'Maestro'
    assert_file_contains "$file" 'bounded self-healing'
  done
}

test_activation_and_root_templates_list_qa_self_heal_skill() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/ACTIVATE.md" \
    "$TEST_ROOT/templates/platform/ACTIVATE-HUB.md" \
    "$TEST_ROOT/.platform/ACTIVATE.md" \
    "$TEST_ROOT/templates/root/CLAUDE.md.template" \
    "$TEST_ROOT/templates/root/CLAUDE.md.hub.template" \
    "$TEST_ROOT/templates/root/AGENTS.md.template" \
    "$TEST_ROOT/templates/root/GEMINI.md.template" \
    "$TEST_ROOT/AGENTS.md"
  do
    assert_file_contains "$file" 'ab-qa-self-heal'
  done
}

test_init_installs_qa_self_heal_skill() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"

  run_and_capture output bash -lc "cd '$dir' && printf '\n\n' | '$TEST_ROOT/bin/ab' init"
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.claude/skills/ab-qa-self-heal/SKILL.md" "Do not stress production"
  assert_file_contains "$dir/.agents/skills/ab-qa-self-heal/SKILL.md" "Do not stress production"
  assert_file_contains "$dir/.platform/roles/qa-automation-engineer.md" "Bound the loop"
}

test_qa_self_heal_skill_exists_in_all_installed_locations
test_qa_self_heal_role_routes_to_bounded_automation
test_role_index_routes_qa_automation_to_self_heal_skill
test_activation_and_root_templates_list_qa_self_heal_skill
test_init_installs_qa_self_heal_skill
