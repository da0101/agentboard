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
    git commit -m "ab init" >/dev/null 2>&1
    "$TEST_ROOT/bin/ab" new-domain auth >/dev/null
    "$TEST_ROOT/bin/ab" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

test_init_scaffolds_memory_files() {
  local dir
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  [[ -f "$dir/.platform/memory/gotchas.md" ]] || fail "memory/gotchas.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/playbook.md" ]] || fail "memory/playbook.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/open-questions.md" ]] || fail "memory/open-questions.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/decisions.md" ]] || fail "memory/decisions.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/log.md" ]] || fail "memory/log.md not scaffolded by init"
  assert_file_contains "$dir/.platform/memory/gotchas.md" "agentboard:gotchas:begin"
  assert_file_contains "$dir/.platform/memory/playbook.md" "agentboard:playbook:begin"
  assert_file_contains "$dir/.platform/memory/open-questions.md" "agentboard:open-questions:active:begin"
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
  python3 - "$dir/.platform/memory/gotchas.md" <<'PY'
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
  assert_contains "$output" "Usage: ab brief"
}

test_brief_warns_about_generic_usage_labels() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "skip: sqlite3 not installed"
    return 0
  }
  local dir output status
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  mkdir -p "$dir/.ab"
  sqlite3 "$dir/.ab/usage.db" "
    CREATE TABLE usage (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
      agent_provider TEXT NOT NULL,
      model TEXT,
      stream_slug TEXT,
      repo TEXT,
      task_type TEXT,
      input_tokens INTEGER,
      output_tokens INTEGER,
      total_tokens INTEGER,
      estimated_cost REAL,
      note TEXT,
      session_id TEXT
    );
    INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens, estimated_cost, note, session_id) VALUES
      ('claude','claude-opus-4-7','watch-install','ab','normal',100000,20000,120000,0,'','a'),
      ('claude','claude-opus-4-7','watch-install','ab','heavy',40000,10000,50000,0,'','b'),
      ('codex','gpt-5.4','other','ab','debug',3000,1000,4000,0,'','c'),
      ('codex','gpt-5.4','other','ab','audit',2000,1000,3000,0,'','d'),
      ('codex','gpt-5.4','other','ab','research',2500,1200,3700,0,'','e');
  "
  set +e
  output="$(cd "$dir" && env HOME="$dir" "$TEST_ROOT/bin/ab" brief 2>&1)"
  status=$?
  set -e
  RUN_STATUS="$status"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "generic labels like normal/heavy"
}

for t in \
  test_init_scaffolds_memory_files \
  test_brief_shows_active_stream \
  test_brief_shows_gotchas_when_present \
  test_brief_reports_empty_state_gracefully \
  test_brief_help \
  test_brief_warns_about_generic_usage_labels; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
