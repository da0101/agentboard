#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

test_workflow_defines_silicon_valley_product_mindset() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/workflow.md" \
    "$TEST_ROOT/.platform/workflow.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Silicon Valley product mindset"
    assert_file_contains "$file" "best-in-class Silicon Valley product team"
    assert_file_contains "$file" "differentiated, durable"
    assert_file_contains "$file" "not permission for vague hype or scope creep"
    assert_file_contains "$file" "human approval"
    assert_file_contains "$file" "change. PM work"
  done
}

test_role_index_makes_mindset_a_baseline() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/roles/INDEX.md" \
    "$TEST_ROOT/.platform/roles/INDEX.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Silicon Valley product"
    assert_file_contains "$file" "best-in-class"
    assert_file_contains "$file" "scope discipline"
    assert_file_contains "$file" "human approval gates"
  done
}

test_pm_and_engineering_roles_apply_mindset_with_guardrails() {
  local file
  for file in \
    "$TEST_ROOT/templates/platform/roles/product-manager.md" \
    "$TEST_ROOT/templates/platform/roles/feature-builder.md" \
    "$TEST_ROOT/templates/platform/roles/startup-mvp.md" \
    "$TEST_ROOT/.platform/roles/product-manager.md" \
    "$TEST_ROOT/.platform/roles/feature-builder.md" \
    "$TEST_ROOT/.platform/roles/startup-mvp.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Silicon Valley product mindset"
    assert_file_contains "$file" "best-in-class"
    assert_file_contains "$file" "scope"
    assert_file_contains "$file" "approved"
  done
}

test_entry_templates_expose_mindset_to_all_providers() {
  local file
  for file in \
    "$TEST_ROOT/templates/root/CLAUDE.md.template" \
    "$TEST_ROOT/templates/root/CLAUDE.md.hub.template" \
    "$TEST_ROOT/templates/root/AGENTS.md.template" \
    "$TEST_ROOT/templates/root/GEMINI.md.template"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Silicon Valley product mindset"
    assert_file_contains "$file" "best-in-class Silicon Valley product teams"
    assert_file_contains "$file" "scope creep"
    assert_file_contains "$file" ".platform/workflow.md"
  done
}

test_current_repo_entry_files_expose_mindset() {
  local file
  for file in \
    "$TEST_ROOT/AGENTS.md" \
    "$TEST_ROOT/CLAUDE.md" \
    "$TEST_ROOT/GEMINI.md"
  do
    [[ -f "$file" ]] || fail "$file missing"
    assert_file_contains "$file" "Silicon"
    assert_file_contains "$file" "Valley product"
    assert_file_contains "$file" "user-obsessed"
    assert_file_contains "$file" "scope"
    assert_file_contains "$file" "human approval"
  done
}

test_workflow_defines_silicon_valley_product_mindset
test_role_index_makes_mindset_a_baseline
test_pm_and_engineering_roles_apply_mindset_with_guardrails
test_entry_templates_expose_mindset_to_all_providers
test_current_repo_entry_files_expose_mindset
