#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# Fixture: a project with two layered knowledge cards and a few knowledge rows.
setup_recall_fixture() {
  RC_DIR="$(mktemp -d)"
  mkdir -p "$RC_DIR/.platform/domains" "$RC_DIR/.platform/knowledge"
  printf '# Template\n' > "$RC_DIR/.platform/domains/TEMPLATE.md"
  cat > "$RC_DIR/.platform/domains/questionnaires.md" <<'EOF'
---
domain_id: dom-questionnaires
slug: questionnaires
repo_ids: [api-server, web-app, mobile-app]
updated_at: 2026-10-01
---

# Domain: Questionnaires

Scored patient questionnaires with recurrence and score-colour bands.

## Backend (api-server)
- `Questionnaire` model in `questionnaire/models.py`; score bands live in `ScoreColour`.
- Endpoint `POST /api/questionnaires/` validates band overlap.

## Web (web-app)
- Builder UI in `src/questionnaire/builder/`; bands edited in `ScoreColourEditor`.

## Mobile (mobile-app)
- Filler screen `QuestionnaireScreen`; offline queue in `QuestionnaireQueue`.
EOF
  cat > "$RC_DIR/.platform/domains/billing.md" <<'EOF'
---
domain_id: dom-billing
slug: billing
repo_ids: [api-server]
updated_at: 2026-09-01
---

# Domain: Billing

## Backend (api-server)
- Invoices in `billing/invoice.py`.
EOF
  printf '%s\n' '{"type":"learning","id":"L-1","title":"Questionnaire score colour bands must not overlap","body":"x"}' \
    '{"type":"learning","id":"L-2","title":"Invoice rounding drifts by one cent","body":"y"}' \
    > "$RC_DIR/.platform/knowledge/learnings.jsonl"
  printf '%s\n' '{"type":"decision","topic":"Questionnaire recurrence stored as RRULE","decision":"d"}' \
    > "$RC_DIR/.platform/knowledge/decisions.jsonl"
}

test_recall_returns_matching_card_by_slug() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "recall: questionnaires"
  assert_contains "$output" "api-server,web-app,mobile-app"
  assert_contains "$output" "updated 2026-10-01"
  assert_contains "$output" "## Backend (api-server)"
  assert_not_contains "$output" "Invoices in"
}

test_recall_matches_on_body_when_slug_does_not() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall invoice
  assert_contains "$output" "recall: billing"
}

test_recall_layer_returns_only_matching_sections() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires --layer mobile
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "QuestionnaireQueue"
  assert_not_contains "$output" "ScoreColour"
  assert_not_contains "$output" "Scored patient questionnaires"
}

test_recall_multiple_layers_are_combined() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires --layer backend --layer web
  assert_contains "$output" "questionnaire/models.py"
  assert_contains "$output" "ScoreColourEditor"
  assert_not_contains "$output" "QuestionnaireQueue"
}

test_recall_unknown_layer_lists_available_sections() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires --layer firmware
  assert_contains "$output" "No section matches"
  assert_contains "$output" "## Mobile (mobile-app)"
}

test_recall_budget_truncates_and_names_what_was_left_out() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires --budget 30 --no-related
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "truncated"
  assert_contains "$output" "## Mobile (mobile-app)"
  assert_not_contains "$output" "QuestionnaireQueue"
}

test_recall_no_match_says_so() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall zebra
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No card matches"
}

test_recall_includes_related_knowledge_unless_disabled() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall questionnaires
  assert_contains "$output" "Related knowledge"
  assert_contains "$output" "Questionnaire score colour bands must not overlap"
  assert_contains "$output" "Questionnaire recurrence stored as RRULE"
  assert_not_contains "$output" "Invoice rounding"
  run_cli_capture output "$RC_DIR" recall questionnaires --no-related
  assert_not_contains "$output" "Related knowledge"
}

test_recall_top_prints_multiple_cards() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall api-server --top 2
  assert_contains "$output" "recall: questionnaires"
  assert_contains "$output" "recall: billing"
}

test_recall_list_shows_cards_without_template() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall --list
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "questionnaires"
  assert_contains "$output" "billing"
  assert_contains "$output" "Scored patient questionnaires"
  assert_not_contains "$output" "TEMPLATE"
}

test_recall_requires_a_topic_or_list() {
  local output
  setup_recall_fixture
  run_cli_capture output "$RC_DIR" recall
  [[ "$RUN_STATUS" -ne 0 ]] || fail "recall with no topic should fail"
  assert_contains "$output" "Usage: ab recall"
}

test_recall_fails_outside_a_project() {
  local output dir
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" recall anything
  [[ "$RUN_STATUS" -ne 0 ]] || fail "recall outside a project should fail"
}

test_recall_returns_matching_card_by_slug
test_recall_matches_on_body_when_slug_does_not
test_recall_layer_returns_only_matching_sections
test_recall_multiple_layers_are_combined
test_recall_unknown_layer_lists_available_sections
test_recall_budget_truncates_and_names_what_was_left_out
test_recall_no_match_says_so
test_recall_includes_related_knowledge_unless_disabled
test_recall_top_prints_multiple_cards
test_recall_list_shows_cards_without_template
test_recall_requires_a_topic_or_list
test_recall_fails_outside_a_project
