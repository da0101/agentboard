#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1
export AGENTBOARD_COLD_DIR="$(mktemp -d)"

# A project with card "auth" (api repo) and an approved stream "login".
setup_ck_fixture() {
  CK_DIR="$(mktemp -d)"
  printf '{}\n' > "$CK_DIR/package.json"
  make_git_repo "$CK_DIR" main
  commit_all "$CK_DIR" initial
  init_project_fixture "$CK_DIR"
  (
    cd "$CK_DIR"
    git add .platform .claude CLAUDE.md
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth api >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login --domain auth --base-branch main --branch feat/login >/dev/null
  )
  CK_CARD="$CK_DIR/.platform/domains/auth.md"
  CK_STREAM="$CK_DIR/.platform/work/login.md"
  local tmp; tmp="$(mktemp)"
  awk '/^closure_approved:/ { print "closure_approved: true"; next } { print }' "$CK_STREAM" > "$tmp"
  mv "$tmp" "$CK_STREAM"
}

# Replace the card body with a known layered layout.
seed_card() {
  cat > "$CK_CARD" <<'EOF'
---
domain_id: dom-auth
slug: auth
status: active
repo_ids: [api, web]
related_domain_slugs: []
created_at: 2026-01-01
updated_at: 2026-01-01
---

# Domain: Auth

## Backend (api)
- [token-ttl] old: tokens live 24h
- [legacy-login] `POST /v1/login` still exists
- free prose line that must survive

## Web (web)
- [login-form] old form lives in `src/Login.tsx`
EOF
}

add_delta() {
  { printf '\n## Knowledge delta\n'; cat; } >> "$CK_STREAM"
}

count_key() { grep -c "^- \[$1\]" "$CK_CARD" || true; }

test_delta_adds_a_new_fact_with_provenance_in_the_matching_section() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | backend
- [rate-limit] 5 attempts/min per IP in `auth/throttle.py`
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "[rate-limit] added"
  assert_file_contains "$CK_CARD" "- [rate-limit] 5 attempts/min per IP in \`auth/throttle.py\` (login, "
  # lands inside the Backend section, before the Web heading
  local backend_line web_line fact_line
  backend_line="$(grep -n '^## Backend' "$CK_CARD" | cut -d: -f1)"
  web_line="$(grep -n '^## Web' "$CK_CARD" | cut -d: -f1)"
  fact_line="$(grep -n '^- \[rate-limit\]' "$CK_CARD" | cut -d: -f1)"
  (( fact_line > backend_line && fact_line < web_line )) || fail "fact was not placed in the Backend section"
}

test_delta_replaces_an_existing_key_without_duplicating_or_losing_prose() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | backend
- [token-ttl] tokens live 30 days (sliding)
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_contains "$output" "[token-ttl] replaced"
  assert_eq "$(count_key token-ttl)" "1"
  assert_file_contains "$CK_CARD" "tokens live 30 days (sliding)"
  assert_file_not_contains "$CK_CARD" "old: tokens live 24h"
  assert_file_contains "$CK_CARD" "free prose line that must survive"
}

test_delta_dash_removes_a_fact_and_reports_unknown_keys() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | backend
- [legacy-login] -
- [never-existed] -
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_contains "$output" "[legacy-login] REMOVED"
  assert_contains "$output" "[never-existed] not found"
  assert_eq "$(count_key legacy-login)" "0"
}

test_delta_creates_a_missing_layer_section_and_a_missing_card() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | mobile
- [biometric] Face ID unlock via `BiometricGate`
### billing | backend
- [invoice] invoices in `billing/invoice.py`
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_file_contains "$CK_CARD" "## Mobile"
  assert_file_contains "$CK_CARD" "[biometric] Face ID unlock via \`BiometricGate\`"
  assert_contains "$output" "new card: billing"
  assert_file_contains "$CK_DIR/.platform/domains/billing.md" "slug: billing"
  assert_file_contains "$CK_DIR/.platform/domains/billing.md" "[invoice] invoices in"
}

test_delta_preserves_backslashes_and_pipes_in_facts() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | backend
- [paths] windows path C:\dir\new and a | pipe
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_file_contains "$CK_CARD" 'C:\dir\new and a | pipe'
}

test_delta_replaces_a_key_that_lives_in_a_later_matching_section() {
  local output
  setup_ck_fixture
  cat > "$CK_CARD" <<'EOF'
---
domain_id: dom-auth
slug: auth
status: active
repo_ids: [api]
related_domain_slugs: []
created_at: 2026-01-01
updated_at: 2026-01-01
---

# Domain: Auth

## Backend / source of truth
- [other] first backend section

## Backend (api)
- [token-ttl] old value in the SECOND backend section
EOF
  add_delta <<'EOF'
### auth | backend
- [token-ttl] new value
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_contains "$output" "[token-ttl] replaced"
  assert_eq "$(count_key token-ttl)" "1"
  assert_file_not_contains "$CK_CARD" "old value in the SECOND"
}

test_dry_run_previews_the_merge_and_leaves_cards_untouched() {
  local output before
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth | backend
- [rate-limit] throttled
EOF
  before="$(cat "$CK_CARD")"
  run_cli_capture output "$CK_DIR" close login --confirm --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "[rate-limit] added"
  assert_eq "$(cat "$CK_CARD")" "$before"
  [[ -f "$CK_STREAM" ]] || fail "dry-run removed the stream"
}

test_close_without_a_delta_warns_but_still_closes() {
  local output
  setup_ck_fixture; seed_card
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No '## Knowledge delta'"
  [[ ! -f "$CK_STREAM" ]] || fail "stream should still close without a delta"
}

test_delta_entry_without_a_layer_is_skipped_with_a_warning() {
  local output
  setup_ck_fixture; seed_card
  add_delta <<'EOF'
### auth
- [orphan] no layer given
EOF
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "skipped [orphan]"
  assert_file_not_contains "$CK_CARD" "[orphan]"
}

test_bullets_outside_the_delta_section_are_ignored() {
  local output
  setup_ck_fixture; seed_card
  printf '\n## Notes\n- [stray] not part of the delta\n' >> "$CK_STREAM"
  add_delta <<'EOF'
### auth | backend
- [real] counts
EOF
  printf '\n## Later section\n- [also-stray] ignored\n' >> "$CK_STREAM"
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_file_contains "$CK_CARD" "[real] counts"
  assert_file_not_contains "$CK_CARD" "[stray]"
  assert_file_not_contains "$CK_CARD" "[also-stray]"
}

test_close_distills_a_stream_record_into_the_knowledge_store() {
  local output
  setup_ck_fixture; seed_card
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  [[ -f "$CK_DIR/.platform/knowledge/streams.jsonl" ]] || fail "distill did not run during close"
  assert_file_contains "$CK_DIR/.platform/knowledge/streams.jsonl" '"slug":"login"'
}

test_close_moves_only_this_streams_qa_files_out_of_the_repo() {
  local output qa="$CK_DIR/.platform/work/qa"
  setup_ck_fixture; seed_card
  qa="$CK_DIR/.platform/work/qa"
  mkdir -p "$qa/evidence/login" "$qa/evidence/login-extra"
  printf 'qa\n' > "$qa/login-manual-qa.md"
  printf 'journal\n' > "$qa/login-execution-journal.md"
  printf 'shot\n' > "$qa/evidence/login/a.png"
  # another stream whose slug merely starts with "login"
  printf 'other\n' > "$qa/login-extra-manual-qa.md"
  printf 'other\n' > "$qa/evidence/login-extra/b.png"
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "3 QA item(s) moved"
  [[ ! -e "$qa/login-manual-qa.md" && ! -e "$qa/login-execution-journal.md" && ! -e "$qa/evidence/login" ]] \
    || fail "this stream's QA files must leave the repo"
  [[ -f "$qa/login-extra-manual-qa.md" && -f "$qa/evidence/login-extra/b.png" ]] \
    || fail "another stream's QA files (shared slug prefix) must stay"
  [[ -f "$(ls "$AGENTBOARD_COLD_DIR"/*/closed/login-qa/login-manual-qa.md | tail -1)" ]] \
    || fail "QA copy missing from cold store"
}

test_untouched_template_placeholder_is_ignored_not_merged() {
  local output
  setup_ck_fixture; seed_card
  assert_file_contains "$CK_STREAM" "<domain-slug> | <layer>"
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No '## Knowledge delta'"
  assert_not_contains "$output" "skipped"
  assert_file_not_contains "$CK_CARD" "stable-key"
  [[ ! -f "$CK_DIR/.platform/domains/<domain-slug>.md" ]] || fail "placeholder created a card"
}

test_close_warns_when_a_merged_fact_names_a_path_that_does_not_exist() {
  local output
  setup_ck_fixture; seed_card
  mkdir -p "$CK_DIR/src/auth"; printf 'x\n' > "$CK_DIR/src/auth/throttle.py"
  add_delta <<'EOF2'
### auth | backend
- [rate-limit] throttled in `src/auth/throttle.py`
- [ghost-file] logic lives in `src/auth/imaginary.py`
EOF2
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "match no file"
  assert_contains "$output" "auth: src/auth/imaginary.py"
  assert_not_contains "$output" "throttle.py"
  assert_not_contains "$output" "Login.tsx"   # older drift already in the card is not this stream's doing
}

test_close_is_quiet_about_paths_when_all_exist() {
  local output
  setup_ck_fixture; seed_card
  mkdir -p "$CK_DIR/src/auth"; printf 'x\n' > "$CK_DIR/src/auth/throttle.py"
  add_delta <<'EOF2'
### auth | backend
- [rate-limit] throttled in `src/auth/throttle.py`
EOF2
  run_cli_capture output "$CK_DIR" close login --confirm
  assert_not_contains "$output" "match no file"
}

test_delta_adds_a_new_fact_with_provenance_in_the_matching_section
test_delta_replaces_an_existing_key_without_duplicating_or_losing_prose
test_delta_dash_removes_a_fact_and_reports_unknown_keys
test_delta_creates_a_missing_layer_section_and_a_missing_card
test_delta_preserves_backslashes_and_pipes_in_facts
test_delta_replaces_a_key_that_lives_in_a_later_matching_section
test_dry_run_previews_the_merge_and_leaves_cards_untouched
test_close_without_a_delta_warns_but_still_closes
test_delta_entry_without_a_layer_is_skipped_with_a_warning
test_bullets_outside_the_delta_section_are_ignored
test_close_distills_a_stream_record_into_the_knowledge_store

test_close_moves_only_this_streams_qa_files_out_of_the_repo
test_untouched_template_placeholder_is_ignored_not_merged
test_close_warns_when_a_merged_fact_names_a_path_that_does_not_exist
test_close_is_quiet_about_paths_when_all_exist
