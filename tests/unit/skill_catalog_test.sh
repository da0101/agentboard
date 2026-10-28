#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_skill_fixture() {
  SK_DIR="$(mktemp -d)"
  printf '{}\n' > "$SK_DIR/package.json"
  make_git_repo "$SK_DIR" main
  commit_all "$SK_DIR" initial
  init_project_fixture "$SK_DIR"
}

core_count() { ls -d "$TEST_ROOT"/templates/skills/*/ | wc -l | tr -d ' '; }

test_init_installs_only_the_core_skills() {
  setup_skill_fixture
  assert_eq "$(ls "$SK_DIR/.claude/skills" | wc -l | tr -d ' ')" "$(core_count)"
  assert_eq "$(ls "$SK_DIR/.agents/skills" | wc -l | tr -d ' ')" "$(core_count)"
  [[ -d "$SK_DIR/.claude/skills/ab-workflow" ]] || fail "core skill ab-workflow missing"
  [[ ! -d "$SK_DIR/.claude/skills/ab-canary" ]] || fail "extra skill ab-canary must not be installed by init"
  [[ ! -d "$SK_DIR/.agents/skills/ab-graphify" ]] || fail "extra skill ab-graphify must not be installed by init"
}

test_core_set_is_small() {
  (( $(core_count) <= 14 )) || fail "core skill set grew to $(core_count); extras belong in templates/skills-extra"
}

test_list_shows_tiers_installed_state_and_token_cost() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab-workflow"
  assert_contains "$output" "core"
  assert_contains "$output" "ab-canary"
  assert_contains "$output" "extra"
  assert_contains "$output" "tokens in every session prompt"
}

test_install_adds_an_extra_to_both_provider_dirs_and_is_idempotent() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill install ab-canary
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab-canary installed"
  [[ -f "$SK_DIR/.claude/skills/ab-canary/SKILL.md" ]] || fail "not installed for Claude"
  [[ -f "$SK_DIR/.agents/skills/ab-canary/SKILL.md" ]] || fail "not installed for Codex/Gemini"
  run_cli_capture output "$SK_DIR" skill install ab-canary
  assert_status "$RUN_STATUS" 0
}

test_install_rejects_unknown_names() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill install ab-nonexistent
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown skill should fail"
  assert_contains "$output" "Unknown skill"
}

test_prune_dry_run_removes_nothing() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill install ab-canary ab-tdd
  run_cli_capture output "$SK_DIR" skill prune
  assert_contains "$output" "would remove"
  [[ -d "$SK_DIR/.claude/skills/ab-canary" ]] || fail "dry-run removed a skill"
}

test_prune_apply_removes_unmodified_extras_but_never_core_or_custom_or_edited() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill install ab-canary ab-tdd
  mkdir -p "$SK_DIR/.claude/skills/my-own-skill"; printf -- '---\nname: my-own-skill\n---\n' > "$SK_DIR/.claude/skills/my-own-skill/SKILL.md"
  printf '\nlocal edit\n' >> "$SK_DIR/.claude/skills/ab-tdd/SKILL.md"
  run_cli_capture output "$SK_DIR" skill prune --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -d "$SK_DIR/.claude/skills/ab-canary" ]] || fail "unmodified extra should be removed"
  [[ ! -d "$SK_DIR/.agents/skills/ab-canary" ]] || fail "unmodified extra should be removed from .agents too"
  [[ -d "$SK_DIR/.claude/skills/ab-tdd" ]] || fail "edited extra must be kept"
  assert_contains "$output" "was edited"
  [[ -d "$SK_DIR/.claude/skills/my-own-skill" ]] || fail "user's own skill must never be touched"
  [[ -d "$SK_DIR/.claude/skills/ab-workflow" && -d "$SK_DIR/.claude/skills/ab-review" ]] || fail "core skills must never be pruned"
}

test_update_refreshes_core_without_reinstalling_pruned_extras() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill install ab-canary
  run_cli_capture output "$SK_DIR" skill prune --apply
  rm -rf "$SK_DIR/.claude/skills/ab-review"
  run_cli_capture output "$SK_DIR" update
  assert_status "$RUN_STATUS" 0
  [[ -d "$SK_DIR/.claude/skills/ab-review" ]] || fail "update should restore a missing core skill"
  [[ ! -d "$SK_DIR/.claude/skills/ab-canary" ]] || fail "update must not re-add a pruned extra"
}

test_skill_add_still_requires_a_source() {
  local output
  setup_skill_fixture
  run_cli_capture output "$SK_DIR" skill add
  [[ "$RUN_STATUS" -ne 0 ]] || fail "skill add without a source should fail"
}

test_init_installs_only_the_core_skills
test_core_set_is_small
test_list_shows_tiers_installed_state_and_token_cost
test_install_adds_an_extra_to_both_provider_dirs_and_is_idempotent
test_install_rejects_unknown_names
test_prune_dry_run_removes_nothing
test_prune_apply_removes_unmodified_extras_but_never_core_or_custom_or_edited
test_update_refreshes_core_without_reinstalling_pruned_extras
test_skill_add_still_requires_a_source
