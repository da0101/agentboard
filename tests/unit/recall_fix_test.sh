#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A project whose files moved; cards still name the old locations.
setup_fix_fixture() {
  RF_DIR="$(mktemp -d)"
  make_git_repo "$RF_DIR" main
  mkdir -p "$RF_DIR/src/new/shared" "$RF_DIR/a" "$RF_DIR/b" "$RF_DIR/src/__mocks__" "$RF_DIR/src/new/__tests__"
  printf 'x\n' > "$RF_DIR/src/new/shared/Widget.js"
  printf 'x\n' > "$RF_DIR/a/Dup.js"; printf 'x\n' > "$RF_DIR/b/Dup.js"
  printf 'x\n' > "$RF_DIR/src/__mocks__/api.js"
  printf 'x\n' > "$RF_DIR/src/new/__tests__/Widget.test.js"
  commit_all "$RF_DIR" initial
  RF_DIR="$(cd "$RF_DIR" && pwd -P)"
  mkdir -p "$RF_DIR/.platform/domains"
}

write_fix_card() { # name; body on stdin
  { printf -- '---\ndomain_id: dom-%s\nslug: %s\nstatus: active\nrepo_ids: [x]\nrelated_domain_slugs: []\ncreated_at: 2026-01-01\nupdated_at: 2026-01-02\n---\n\n# %s\n\n' "$1" "$1" "$1"; cat; } > "$RF_DIR/.platform/domains/$1.md"
}

test_a_moved_file_with_one_new_home_is_corrected() {
  local output f
  setup_fix_fixture
  write_fix_card ui <<'EOT'
The widget is in `src/old/Widget.js` and does things.
EOT
  f="$RF_DIR/.platform/domains/ui.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$f" "\`src/new/shared/Widget.js\`"
  assert_file_not_contains "$f" "src/old/Widget.js"
  assert_file_contains "$f" "and does things."
  assert_contains "$output" "1 path(s) corrected"
}

test_preview_writes_nothing() {
  local output f before
  setup_fix_fixture
  write_fix_card ui <<'EOT'
Widget: `src/old/Widget.js`.
EOT
  f="$RF_DIR/.platform/domains/ui.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix
  assert_contains "$output" "preview"
  assert_contains "$output" "src/new/shared/Widget.js"
  assert_eq "$(cat "$f")" "$before"
}

test_same_named_files_in_several_places_are_ambiguous_and_untouched() {
  local output f before
  setup_fix_fixture
  write_fix_card dup <<'EOT'
Dup lives in `src/old/Dup.js`.
EOT
  f="$RF_DIR/.platform/domains/dup.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_contains "$output" "Ambiguous"
  assert_contains "$output" "1 ambiguous"
  assert_eq "$(cat "$f")" "$before"
}

test_a_file_that_exists_nowhere_is_reported_as_gone_and_untouched() {
  local output f before
  setup_fix_fixture
  write_fix_card gone <<'EOT'
Removed: `src/old/Nothing.js`.
EOT
  f="$RF_DIR/.platform/domains/gone.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_contains "$output" "Gone"
  assert_contains "$output" "1 gone"
  assert_eq "$(cat "$f")" "$before"
}

test_a_mock_or_test_directory_is_not_accepted_as_the_new_home() {
  local output f before
  setup_fix_fixture
  write_fix_card api <<'EOT'
The client is `src/redux/api.js`.
EOT
  f="$RF_DIR/.platform/domains/api.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_not_contains "$output" "__mocks__"
  assert_contains "$output" "1 gone"
  assert_eq "$(cat "$f")" "$before"
}

test_a_test_file_may_move_to_another_test_directory() {
  local output f
  setup_fix_fixture
  write_fix_card t <<'EOT'
Test: `src/old/__tests__/Widget.test.js`.
EOT
  f="$RF_DIR/.platform/domains/t.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_file_contains "$f" "src/new/__tests__/Widget.test.js"
}

test_only_whole_path_tokens_are_replaced() {
  local output f
  setup_fix_fixture
  write_fix_card tok <<'EOT'
Short `src/old/Widget.js` and long `other/src/old/Widget.js` and `x-src/old/Widget.js`.
EOT
  f="$RF_DIR/.platform/domains/tok.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_file_not_contains "$f" "other/src/new"
  assert_file_not_contains "$f" "x-src/new"
  assert_eq "$(grep -o 'src/new/shared/Widget.js' "$f" | wc -l | tr -d ' ')" "3"
}

test_line_and_symbol_suffixes_survive() {
  local output f
  setup_fix_fixture
  write_fix_card suf <<'EOT'
See `src/old/Widget.js:42` and `src/old/Widget.js::render`.
EOT
  f="$RF_DIR/.platform/domains/suf.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_file_contains "$f" "src/new/shared/Widget.js:42"
  assert_file_contains "$f" "src/new/shared/Widget.js::render"
}

test_apply_backs_up_bumps_updated_at_and_is_idempotent() {
  local output f cold
  setup_fix_fixture
  export AGENTBOARD_COLD_DIR="$(mktemp -d)"
  write_fix_card ui <<'EOT'
Widget: `src/old/Widget.js`.
EOT
  f="$RF_DIR/.platform/domains/ui.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  cold="$(ls "$AGENTBOARD_COLD_DIR"/*/recall-fix-*/ui.md | tail -1)"
  assert_file_contains "$cold" "src/old/Widget.js"
  assert_file_not_contains "$f" "updated_at: 2026-01-02"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_contains "$output" "Nothing to fix"
}

test_version_numbers_and_branch_names_are_not_treated_as_files() {
  local output
  setup_fix_fixture
  write_fix_card ver <<'EOT'
Released from `hotfix/6.5.3` and `release/2.4.6`.
EOT
  run_cli_capture output "$RF_DIR" recall --check
  assert_not_contains "$output" "6.5.3"
}

test_gone_paths_say_what_git_knows_about_them() {
  local output
  setup_fix_fixture
  printf 'x\n' > "$RF_DIR/src/Doomed.js"; ( cd "$RF_DIR" && git add -A && git commit -qm "add doomed" && git rm -q src/Doomed.js && git commit -qm "remove doomed" )
  ( cd "$RF_DIR" && git checkout -q -b feature/x && mkdir -p src/future && printf 'x\n' > src/future/Ahead.js && git add -A && git commit -qm "ahead" && git checkout -q main )
  write_fix_card hist <<'EOT'
Old `src/Doomed.js`, future `src/future/Ahead.js`, imaginary `src/Imaginary.js`.
EOT
  run_cli_capture output "$RF_DIR" recall --check --fix
  assert_contains "$output" "3 gone"
  assert_contains "$output" "src/Doomed.js"
  printf '%s\n' "$output" | grep -A1 "src/Doomed.js" | grep -q "deleted" || fail "deleted file should say deleted"
  printf '%s\n' "$output" | grep -A1 "src/future/Ahead.js" | grep -q "only on another branch" || fail "branch-only file should say so"
  printf '%s\n' "$output" | grep -A1 "src/Imaginary.js" | grep -q "never in git history" || fail "unknown file should say never in git history"
}

test_a_javascript_to_typescript_rename_is_followed_when_unambiguous() {
  local output f
  setup_fix_fixture
  mkdir -p "$RF_DIR/src/redux"; printf 'x\n' > "$RF_DIR/src/redux/store.ts"; ( cd "$RF_DIR" && git add -A && git commit -qm ts )
  write_fix_card rn <<'EOT'
Store: `src/redux/store.js`.
EOT
  f="$RF_DIR/.platform/domains/rn.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_file_contains "$f" "src/redux/store.ts"
  assert_file_not_contains "$f" "store.js"
}

test_two_candidate_extensions_are_ambiguous_not_guessed() {
  local output f before
  setup_fix_fixture
  mkdir -p "$RF_DIR/src/ui"; printf 'x\n' > "$RF_DIR/src/ui/Panel.ts"; printf 'x\n' > "$RF_DIR/src/ui/Panel.tsx"; ( cd "$RF_DIR" && git add -A && git commit -qm two )
  write_fix_card amb2 <<'EOT'
Panel: `src/ui/Panel.js`.
EOT
  f="$RF_DIR/.platform/domains/amb2.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_contains "$output" "1 ambiguous"
  assert_eq "$(cat "$f")" "$before"
}

test_an_extension_change_outside_the_js_ts_family_is_not_followed() {
  local output f before
  setup_fix_fixture
  mkdir -p "$RF_DIR/docs"; printf 'x\n' > "$RF_DIR/docs/guide.md"; ( cd "$RF_DIR" && git add -A && git commit -qm docs )
  write_fix_card nf <<'EOT'
Guide: `docs/guide.txt`.
EOT
  f="$RF_DIR/.platform/domains/nf.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_eq "$(cat "$f")" "$before"
}

test_prune_removes_only_bare_bullets_of_git_deleted_files() {
  local output f
  setup_fix_fixture
  printf 'x\n' > "$RF_DIR/src/Doomed.js"; printf 'x\n' > "$RF_DIR/src/Doomed2.js"
  ( cd "$RF_DIR" && git add -A && git commit -qm add && git rm -q src/Doomed.js src/Doomed2.js && git commit -qm rm )
  write_fix_card pr <<'EOT'
## Files
- `src/Doomed.js`
- `src/Doomed2.js` — explains an important invariant worth keeping
- `src/NeverExisted.js`
- `src/new/shared/Widget.js`
EOT
  f="$RF_DIR/.platform/domains/pr.md"
  run_cli_capture output "$RF_DIR" recall --check --fix --prune --apply
  assert_contains "$output" "1 bare bullet(s) removed"
  assert_file_not_contains "$f" "- \`src/Doomed.js\`"
  assert_file_contains "$f" "src/Doomed2.js"
  assert_file_contains "$f" "explains an important invariant worth keeping"
  assert_file_contains "$f" "src/NeverExisted.js"
  assert_file_contains "$f" "src/new/shared/Widget.js"
}

test_prune_is_opt_in_and_preview_writes_nothing() {
  local output f before
  setup_fix_fixture
  printf 'x\n' > "$RF_DIR/src/Doomed.js"; ( cd "$RF_DIR" && git add -A && git commit -qm add && git rm -q src/Doomed.js && git commit -qm rm )
  write_fix_card op <<'EOT'
- `src/Doomed.js`
EOT
  f="$RF_DIR/.platform/domains/op.md"; before="$(cat "$f")"
  run_cli_capture output "$RF_DIR" recall --check --fix --apply
  assert_eq "$(cat "$f")" "$before"
  run_cli_capture output "$RF_DIR" recall --check --fix --prune
  assert_contains "$output" "would be removed"
  assert_eq "$(cat "$f")" "$before"
}

test_unknown_fix_flags_are_rejected() {
  local output
  setup_fix_fixture
  run_cli_capture output "$RF_DIR" recall --check --fix --bogus
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown flag should fail"
}

test_a_moved_file_with_one_new_home_is_corrected
test_preview_writes_nothing
test_same_named_files_in_several_places_are_ambiguous_and_untouched
test_a_file_that_exists_nowhere_is_reported_as_gone_and_untouched
test_a_mock_or_test_directory_is_not_accepted_as_the_new_home
test_a_test_file_may_move_to_another_test_directory
test_only_whole_path_tokens_are_replaced
test_line_and_symbol_suffixes_survive
test_apply_backs_up_bumps_updated_at_and_is_idempotent
test_version_numbers_and_branch_names_are_not_treated_as_files
test_gone_paths_say_what_git_knows_about_them
test_a_javascript_to_typescript_rename_is_followed_when_unambiguous
test_two_candidate_extensions_are_ambiguous_not_guessed
test_an_extension_change_outside_the_js_ts_family_is_not_followed
test_prune_removes_only_bare_bullets_of_git_deleted_files
test_prune_is_opt_in_and_preview_writes_nothing
test_unknown_fix_flags_are_rejected
