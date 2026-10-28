#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A legacy activated entry file: project facts, duplicated procedure, and a
# preserved block of the user's own pre-activation text.
write_legacy_entry() {
  local f="$1" pad="${2:-0}" i
  cat > "$f" <<'EOT'
# Demo Platform

**What this is:** a clinical platform. Two apps share one backend.

---

## The Repos

| Repo | Stack |
|---|---|
| api | Django |

## Clinical workflow engine

Workflows are stored as decision trees; the engine lives in `api/workflow/`.

## Workflow for editing this repo

Follow the six stages; never push to main.

## Workflow

### Session Start (Every Session)

1. Run `agentboard brief` first.

### During Work

- Never commit or push unless the user explicitly asks for it in the current conversation.
- After significant edits, run `agentboard log-reason`.

## Reference Pack (`.platform/`)

| File | What |
|---|---|
| `architecture.md` | topology |

## Hard Constraints

1. Always scope queries by clinic id.

## Custom Billing Notes

Invoices round half-up.

## Subagent Dispatch

Always pass `model` explicitly on every `Task` call — never omit it (omitting inherits the caller and wastes tokens).

## Skills available

`ab-triage`, `ab-workflow`
EOT
  for ((i = 1; i <= pad; i++)); do
    printf '\n## Active Work (part %s)\n\nSome repeated procedure text that the kernel already covers, line %s.\n' "$i" "$i" >> "$f"
  done
  cat >> "$f" <<'EOT'
## Existing CLAUDE.md content (preserved by agentboard activation on 2026-04-13)

# my own notes

Keep this exact line. It is the user's own text.
EOT
}

setup_adopt_fixture() {
  AD_DIR="$(mktemp -d)"
  printf '{}\n' > "$AD_DIR/package.json"
  make_git_repo "$AD_DIR" main
  commit_all "$AD_DIR" initial
  init_project_fixture "$AD_DIR"
  write_legacy_entry "$AD_DIR/CLAUDE.md"
}

test_preview_classifies_sections_and_changes_nothing() {
  local output before
  setup_adopt_fixture
  before="$(cat "$AD_DIR/CLAUDE.md")"
  run_cli_capture output "$AD_DIR" entry adopt
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "preview"
  assert_contains "$output" "DROP"
  assert_contains "$output" "Workflow"
  assert_eq "$(cat "$AD_DIR/CLAUDE.md")" "$before"
}

test_headings_are_matched_at_the_start_so_project_sections_survive() {
  local output
  setup_adopt_fixture
  run_cli_capture output "$AD_DIR" entry adopt
  assert_contains "$output" "keep      "
  # "Clinical workflow engine" contains "workflow" but is project knowledge
  printf '%s\n' "$output" | grep -E "keep .*Clinical workflow engine" >/dev/null || fail "project section 'Clinical workflow engine' must be kept"
  printf '%s\n' "$output" | grep -E "keep .*Custom Billing Notes" >/dev/null || fail "unclassifiable section must be kept"
  printf '%s\n' "$output" | grep -E "DROP .*Workflow$" >/dev/null || fail "generic 'Workflow' section should be dropped"
  printf '%s\n' "$output" | grep -E "keep .*Workflow for editing this repo" >/dev/null || fail "'Workflow for editing this repo' is project text and must be kept"
}

test_apply_keeps_project_facts_drops_procedure_and_inserts_the_kernel() {
  local output f="$AD_DIR/CLAUDE.md"
  setup_adopt_fixture; f="$AD_DIR/CLAUDE.md"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$f" "agentboard:root-entry:begin"
  assert_file_contains "$f" "agentboard:root-entry:end"
  assert_file_contains "$f" "agentboard:kernel:begin"
  assert_file_contains "$f" "## The Repos"
  assert_file_contains "$f" "Clinical workflow engine"
  assert_file_contains "$f" "Custom Billing Notes"
  assert_file_contains "$f" "Always scope queries by clinic id"
  assert_file_not_contains "$f" "Session Start (Every Session)"
  assert_file_not_contains "$f" "## Reference Pack"
  assert_file_not_contains "$f" "## Skills available"
  assert_file_contains "$f" "Claude Code:"
}

test_apply_carries_over_rules_the_kernel_does_not_state() {
  local output f
  setup_adopt_fixture; f="$AD_DIR/CLAUDE.md"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_contains "$output" "carried over"
  assert_file_contains "$f" "## Carried-over rules"
  assert_file_contains "$f" "Never commit or push unless the user explicitly asks"
}

test_apply_preserves_the_users_own_text_verbatim_after_the_markers() {
  local output f end_line tail_line
  setup_adopt_fixture; f="$AD_DIR/CLAUDE.md"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_file_contains "$f" "Keep this exact line. It is the user's own text."
  end_line="$(grep -n 'agentboard:root-entry:end' "$f" | cut -d: -f1)"
  tail_line="$(grep -n "Keep this exact line" "$f" | cut -d: -f1)"
  (( tail_line > end_line )) || fail "user text must sit after the end marker"
}

test_apply_backs_up_the_original_to_the_cold_store() {
  local output backup
  setup_adopt_fixture
  run_cli_capture output "$AD_DIR" entry adopt --apply
  backup="$(ls "$AGENTBOARD_COLD_DIR"/*/adopt-*/CLAUDE.md 2>/dev/null | tail -1)"
  [[ -f "$backup" ]] || fail "no backup of the original entry file"
  assert_file_contains "$backup" "Session Start (Every Session)"
}

test_apply_shrinks_the_session_start_budget() {
  local output before after
  setup_adopt_fixture
  write_legacy_entry "$AD_DIR/CLAUDE.md" 60
  run_cli_capture output "$AD_DIR" entry check
  before="$(printf '%s\n' "$output" | sed -n 's/.*Session start ≈ \([0-9]*\) tokens.*/\1/p')"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  run_cli_capture output "$AD_DIR" entry check
  after="$(printf '%s\n' "$output" | sed -n 's/.*Session start ≈ \([0-9]*\) tokens.*/\1/p')"
  (( after < before )) || fail "session start did not shrink ($before -> $after)"
  (( before - after > 400 )) || fail "expected a substantial saving, got $before -> $after"
}

test_keep_and_drop_override_the_classification() {
  local output f
  setup_adopt_fixture; f="$AD_DIR/CLAUDE.md"
  run_cli_capture output "$AD_DIR" entry adopt --apply --keep "Reference Pack" --drop "Custom Billing"
  assert_file_contains "$f" "## Reference Pack"
  assert_file_not_contains "$f" "Custom Billing Notes"
}

test_already_adopted_or_marked_files_are_skipped() {
  local output before
  setup_adopt_fixture
  run_cli_capture output "$AD_DIR" entry adopt --apply
  before="$(cat "$AD_DIR/CLAUDE.md")"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_contains "$output" "already has Agentboard markers"
  assert_eq "$(cat "$AD_DIR/CLAUDE.md")" "$before"
}

test_each_file_gets_its_own_provider_note() {
  local output
  setup_adopt_fixture
  write_legacy_entry "$AD_DIR/AGENTS.md"; write_legacy_entry "$AD_DIR/GEMINI.md"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_file_contains "$AD_DIR/AGENTS.md" "Codex CLI:"
  assert_file_contains "$AD_DIR/GEMINI.md" "Gemini CLI:"
  assert_file_not_contains "$AD_DIR/AGENTS.md" "Claude Code:"
}

test_adopt_without_a_project_fails_and_bad_flags_fail() {
  local output dir
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" entry adopt
  [[ "$RUN_STATUS" -ne 0 ]] || fail "adopt outside a project should fail"
  setup_adopt_fixture
  run_cli_capture output "$AD_DIR" entry adopt --bogus
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown flag should fail"
}

test_fresh_stubs_that_already_carry_the_kernel_are_left_alone() {
  local output before
  setup_adopt_fixture
  before="$(cat "$AD_DIR/AGENTS.md")"
  assert_file_contains "$AD_DIR/AGENTS.md" "agentboard:kernel:begin"
  run_cli_capture output "$AD_DIR" entry adopt --apply
  assert_contains "$output" "AGENTS.md: already carries the kernel"
  assert_eq "$(cat "$AD_DIR/AGENTS.md")" "$before"
  assert_eq "$(grep -c 'agentboard:kernel:begin' "$AD_DIR/CLAUDE.md")" "1"
}

test_preview_classifies_sections_and_changes_nothing
test_headings_are_matched_at_the_start_so_project_sections_survive
test_apply_keeps_project_facts_drops_procedure_and_inserts_the_kernel
test_apply_carries_over_rules_the_kernel_does_not_state
test_apply_preserves_the_users_own_text_verbatim_after_the_markers
test_apply_backs_up_the_original_to_the_cold_store
test_apply_shrinks_the_session_start_budget
test_keep_and_drop_override_the_classification
test_already_adopted_or_marked_files_are_skipped
test_each_file_gets_its_own_provider_note
test_adopt_without_a_project_fails_and_bad_flags_fail
test_fresh_stubs_that_already_carry_the_kernel_are_left_alone
