#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# An "old" project: git repo, activated .platform, plus the pollution the lean layout removes.
setup_old_project() {
  UP="$(mktemp -d)"; UP="$(cd "$UP" && pwd -P)"
  mkdir -p "$UP/src"; printf 'x\n' > "$UP/src/app.py"
  make_git_repo "$UP" main; commit_all "$UP" initial
  init_project_fixture "$UP"
  mkdir -p "$UP/.platform/work/archive" "$UP/.platform/graphify" "$UP/.platform/domains"
  printf 'old stream\n' > "$UP/.platform/work/archive/old-stream.md"
  printf '{}\n' > "$UP/.platform/graphify/graph.json"
  printf 'raw transcript\n' > "$UP/.platform/memory/session-2026-01-01.md"
  printf -- '---\nslug: app\nrepo_ids: [x]\nupdated_at: 2026-10-01\n---\n\n# Domain: app\n\nThe app lives in `src/app.py`, plus a gone file `src/removed.py`.\n' > "$UP/.platform/domains/app.md"
  commit_all "$UP" "old project"
  export AGENTBOARD_COLD_DIR="$UP/cold"
}

test_preview_changes_nothing_and_says_how_to_apply() {
  local out before
  setup_old_project
  before="$(cd "$UP" && git status --porcelain | wc -l | tr -d ' ')"
  run_cli_capture out "$UP" upgrade
  assert_status "$RUN_STATUS" 0
  assert_contains "$out" "preview"; assert_contains "$out" "--apply"
  [[ -f "$UP/.platform/work/archive/old-stream.md" && -f "$UP/.platform/graphify/graph.json" ]] || fail "preview must not move anything"
  [[ ! -e "$UP/cold" ]] || fail "preview must not write a backup"
  [[ "$(cd "$UP" && git status --porcelain | wc -l | tr -d ' ')" == "$before" ]] || fail "preview changed the working tree"
}

test_apply_removes_pollution_keeps_knowledge_and_saves_a_backup() {
  local out
  setup_old_project
  run_cli_capture out "$UP" upgrade --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -e "$UP/.platform/work/archive/old-stream.md" ]] || fail "archive should have left the repo"
  [[ ! -e "$UP/.platform/graphify/graph.json" ]] || fail "graph should have left the repo"
  [[ ! -e "$UP/.platform/memory/session-2026-01-01.md" ]] || fail "session dump should have left the repo"
  assert_file_contains "$UP/.platform/domains/app.md" "src/app.py"          # knowledge untouched
  [[ -s "$UP/.platform/CARDS.md" ]] || fail "card index should exist"
  assert_file_contains "$UP/.platform/CARDS.md" "domains/app.md"
  ls "$UP"/cold/*/pre-upgrade-*.tgz >/dev/null 2>&1 || fail "pre-upgrade backup missing"
  assert_contains "$out" "before"; assert_contains "$out" "stale card paths"
  assert_contains "$out" "Only you can do"
}

test_apply_twice_is_a_no_op_the_second_time() {
  local out status1 status2
  setup_old_project
  run_cli_capture out "$UP" upgrade --apply
  status1="$(cd "$UP" && git status --porcelain | sort)"
  run_cli_capture out "$UP" upgrade --apply
  status2="$(cd "$UP" && git status --porcelain | sort)"
  assert_eq "$status1" "$status2"
}

test_upgrade_outside_a_project_explains_itself() {
  local out d
  d="$(mktemp -d)"
  run_cli_capture out "$d" upgrade
  assert_contains "$out" "No .platform/"
}

test_preview_changes_nothing_and_says_how_to_apply
test_apply_removes_pollution_keeps_knowledge_and_saves_a_backup
test_apply_twice_is_a_no_op_the_second_time
test_upgrade_outside_a_project_explains_itself
