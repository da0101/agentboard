#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_brief_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

test_init_scaffolds_memory_files() {
  local dir
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  [[ -f "$dir/.platform/gotchas.md" ]] || fail "gotchas.md not scaffolded by init"
  [[ -f "$dir/.platform/playbook.md" ]] || fail "playbook.md not scaffolded by init"
  [[ -f "$dir/.platform/open-questions.md" ]] || fail "open-questions.md not scaffolded by init"
  assert_file_contains "$dir/.platform/gotchas.md" "agentboard:gotchas:begin"
  assert_file_contains "$dir/.platform/playbook.md" "agentboard:playbook:begin"
  assert_file_contains "$dir/.platform/open-questions.md" "agentboard:open-questions:active:begin"
}

test_brief_shows_active_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief
  if (( RUN_STATUS != 0 )); then
    printf 'brief output (status=%s):\n%s\n' "$RUN_STATUS" "$output" >&2
  fi
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Active streams"
  assert_contains "$output" "login"
}

test_brief_shows_gotchas_when_present() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  # Insert a 🔴 gotcha between markers
  python3 - "$dir/.platform/gotchas.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
content = p.read_text()
content = content.replace(
    "<!-- agentboard:gotchas:begin -->",
    "<!-- agentboard:gotchas:begin -->\n🔴 [auth] — never refactor middleware without running integration suite (mocks lie)",
    1,
)
p.write_text(content)
PY
  run_cli_capture output "$dir" brief
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Gotchas"
  assert_contains "$output" "never refactor middleware"
}

test_brief_reports_empty_state_gracefully() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "none yet"
}

test_brief_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard brief"
}

for t in \
  test_init_scaffolds_memory_files \
  test_brief_shows_active_stream \
  test_brief_shows_gotchas_when_present \
  test_brief_reports_empty_state_gracefully \
  test_brief_help; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
