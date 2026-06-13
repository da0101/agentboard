#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

test_cleanup_skill_uses_graph_json_contract() {
  local file
  for file in \
    "$TEST_ROOT/templates/skills/ab-cleanup/SKILL.md" \
    "$TEST_ROOT/.claude/skills/ab-cleanup/SKILL.md" \
    "$TEST_ROOT/.agents/skills/ab-cleanup/SKILL.md"
  do
    assert_file_contains "$file" '.platform/graphify/graph.json'
    assert_file_not_contains "$file" '.platform/graphify/GRAPH_REPORT.md'
  done
}

test_cleanup_role_uses_graph_json_contract() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/roles/code-cleanup-engineer.md" \
    "$TEST_ROOT/.platform/roles/code-cleanup-engineer.md"
  do
    assert_file_contains "$file" 'Graphify `graph.json` output'
    assert_file_not_contains "$file" 'Graphify reports'
  done
}

test_activation_skill_table_uses_graph_json_contract() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/ACTIVATE.md" \
    "$TEST_ROOT/templates/platform/ACTIVATE-HUB.md" \
    "$TEST_ROOT/.platform/ACTIVATE.md"
  do
    assert_file_contains "$file" '.platform/graphify/graph.json'
    assert_file_contains "$file" 'AST-only mode'
    assert_file_not_contains "$file" 'Reference `GRAPH_REPORT.md`'
  done
}

test_init_installs_cleanup_skill_with_graph_json_contract() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"

  run_and_capture output bash -lc "cd '$dir' && printf '\n\n' | '$TEST_ROOT/bin/ab' init"
  assert_file_contains "$dir/.claude/skills/ab-cleanup/SKILL.md" '.platform/graphify/graph.json'
  assert_file_contains "$dir/.agents/skills/ab-cleanup/SKILL.md" '.platform/graphify/graph.json'
  assert_file_not_contains "$dir/.claude/skills/ab-cleanup/SKILL.md" '.platform/graphify/GRAPH_REPORT.md'
  assert_file_not_contains "$dir/.agents/skills/ab-cleanup/SKILL.md" '.platform/graphify/GRAPH_REPORT.md'
}

test_cleanup_skill_uses_graph_json_contract
test_cleanup_role_uses_graph_json_contract
test_activation_skill_table_uses_graph_json_contract
test_init_installs_cleanup_skill_with_graph_json_contract
