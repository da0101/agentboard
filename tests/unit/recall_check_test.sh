#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A single-repo project with real source files and a card that names some of them.
setup_check_fixture() {
  RK_DIR="$(mktemp -d)"
  make_git_repo "$RK_DIR" main
  mkdir -p "$RK_DIR/src/components/forms" "$RK_DIR/src/api"
  printf 'x\n' > "$RK_DIR/src/components/forms/FormView.tsx"
  printf 'x\n' > "$RK_DIR/src/api/client.ts"
  commit_all "$RK_DIR" initial
  RK_DIR="$(cd "$RK_DIR" && pwd -P)"
}

write_card() { # name body...
  local name="$1"; shift
  mkdir -p "$RK_DIR/.platform/domains"
  { printf -- '---\nslug: %s\nrepo_ids: [x]\nupdated_at: 2026-10-01\n---\n\n# Domain: %s\n\n' "$name" "$name"; cat; } > "$RK_DIR/.platform/domains/$name.md"
}

test_check_passes_when_every_named_file_exists() {
  local output
  setup_check_fixture
  write_card forms <<'EOF'
## Web
- Form view lives in `src/components/forms/FormView.tsx`; client in `src/api/client.ts`.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "resolve to a real file"
  assert_not_contains "$output" "match no file"
}

test_check_reports_a_path_that_no_longer_exists() {
  local output
  setup_check_fixture
  write_card forms <<'EOF'
## Web
- Old home: `src/components/forms/LegacyForm.tsx` and current `src/api/client.ts`.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "forms — 1 of 2 path(s) match no file"
  assert_contains "$output" "src/components/forms/LegacyForm.tsx"
  assert_not_contains "$output" "- src/api/client.ts"
}

test_check_accepts_abbreviated_paths_that_end_a_real_file() {
  local output
  setup_check_fixture
  write_card forms <<'EOF'
- Shorthand `forms/FormView.tsx` and `components/forms/FormView.tsx` both mean the real file.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_contains "$output" "resolve to a real file"
}

test_check_strips_line_symbol_and_fragment_suffixes() {
  local output
  setup_check_fixture
  write_card forms <<'EOF'
- See `src/api/client.ts:42`, `src/api/client.ts:10-20`, `src/api/client.ts::fetchAll` and `src/api/client.ts#retry`.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_contains "$output" "resolve to a real file"
}

test_check_ignores_spans_that_are_not_clear_file_paths() {
  local output
  setup_check_fixture
  write_card forms <<'EOF'
- Commands `ab recall --check`, dirs `src/components/forms`, URL `https://example.com/a/b.html`,
  globs `src/**/*.ts`, placeholders `<dir>/file.ts` and `{a,b}/c.ts`, no slash `README.md`, `some code()`.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_contains "$output" "0 file path"
}

test_check_sees_untracked_files_but_not_gitignored_ones() {
  local output
  setup_check_fixture
  printf 'x\n' > "$RK_DIR/src/api/new_untracked.ts"
  printf 'build/\n' > "$RK_DIR/.gitignore"
  mkdir -p "$RK_DIR/build"; printf 'x\n' > "$RK_DIR/build/out.js"
  write_card forms <<'EOF'
- New `src/api/new_untracked.ts`; ignored `build/out.js`.
EOF
  run_cli_capture output "$RK_DIR" recall --check
  assert_contains "$output" "build/out.js"
  assert_not_contains "$output" "new_untracked.ts"
}

test_check_checks_only_the_named_cards() {
  local output
  setup_check_fixture
  write_card good <<'EOF'
- Fine `src/api/client.ts`.
EOF
  write_card bad <<'EOF'
- Gone `src/gone/Missing.ts`.
EOF
  run_cli_capture output "$RK_DIR" recall --check good
  assert_contains "$output" "resolve to a real file"
  run_cli_capture output "$RK_DIR" recall --check bad
  assert_contains "$output" "Missing.ts"
}

test_check_resolves_hub_paths_by_repo_id_and_folder_name() {
  local output base hub
  base="$(mktemp -d)"; hub="$base/hub"; mkdir -p "$hub/.platform/domains" "$base/ApiServer/server"
  make_git_repo "$base/ApiServer" main
  printf 'x\n' > "$base/ApiServer/server/models.py"; commit_all "$base/ApiServer" initial
  make_git_repo "$hub" main
  cat > "$hub/.platform/repos.md" <<'EOF'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
EOF
  RK_DIR="$hub"
  write_card orders <<'EOF'
- By id `api-server/server/models.py`, by folder `ApiServer/server/models.py`, bare `server/models.py`.
- Gone: `api-server/server/removed.py`.
EOF
  run_cli_capture output "$hub" recall --check
  assert_contains "$output" "1 of 4 path(s) match no file"
  assert_contains "$output" "api-server/server/removed.py"
  assert_not_contains "$output" "- api-server/server/models.py"
}

test_doctor_warns_about_drifted_cards_and_passes_when_clean() {
  local output
  setup_check_fixture
  init_project_fixture "$RK_DIR"
  write_card forms <<'EOF'
- Fine `src/api/client.ts`.
EOF
  run_cli_capture output "$RK_DIR" doctor
  assert_contains "$output" "Knowledge cards reference only existing file paths"
  write_card forms <<'EOF'
- Gone `src/gone/Missing.ts`.
EOF
  run_cli_capture output "$RK_DIR" doctor
  assert_contains "$output" "no longer exist"
  assert_contains "$output" "ab recall --check"
}

test_check_passes_when_every_named_file_exists
test_check_reports_a_path_that_no_longer_exists
test_check_accepts_abbreviated_paths_that_end_a_real_file
test_check_strips_line_symbol_and_fragment_suffixes
test_check_ignores_spans_that_are_not_clear_file_paths
test_check_sees_untracked_files_but_not_gitignored_ones
test_check_checks_only_the_named_cards
test_check_resolves_hub_paths_by_repo_id_and_folder_name
test_doctor_warns_about_drifted_cards_and_passes_when_clean
