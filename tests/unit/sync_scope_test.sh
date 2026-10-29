#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A hub project next to one sibling repo that has its own CLAUDE.md.
setup_scope_fixture() {
  SC_BASE="$(mktemp -d)"; SC_HUB="$SC_BASE/hub"; SC_API="$SC_BASE/ApiServer"
  mkdir -p "$SC_HUB" "$SC_API"
  printf '# api team notes\n' > "$SC_API/CLAUDE.md"
  make_git_repo "$SC_API" main; commit_all "$SC_API" initial
  printf '{}\n' > "$SC_HUB/package.json"; make_git_repo "$SC_HUB" main; commit_all "$SC_HUB" initial
  init_project_fixture "$SC_HUB"
  SC_API="$(cd "$SC_API" && pwd -P)"
  cat > "$SC_HUB/.platform/repos.md" <<'EOT'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
EOT
}

repos_in_script() { sed -n '/^REPOS=(/,/^)/p' "$SC_HUB/.platform/scripts/sync-context.sh"; }

test_update_lists_sibling_repos_by_default() {
  local output
  setup_scope_fixture
  run_cli_capture output "$SC_HUB" update
  assert_status "$RUN_STATUS" 0
  [[ "$(repos_in_script)" == *"/ApiServer"* ]] || fail "default behavior should list the sibling repo"
}

test_hub_only_scope_keeps_siblings_out_across_updates() {
  local output
  setup_scope_fixture
  printf '# keep sibling entry files out of sync\nhub-only\n' > "$SC_HUB/.platform/sync-scope"
  run_cli_capture output "$SC_HUB" update
  run_cli_capture output "$SC_HUB" update
  assert_status "$RUN_STATUS" 0
  [[ "$(repos_in_script)" != *"/ApiServer"* ]] || fail "hub-only scope must not list the sibling repo"
  run_cli_capture output "$SC_HUB" sync --list
  assert_contains "$output" "hub"
  assert_not_contains "$output" "ApiServer"
}

test_hub_only_scope_never_touches_the_siblings_entry_files() {
  local output before
  setup_scope_fixture
  printf 'hub-only\n' > "$SC_HUB/.platform/sync-scope"
  before="$(cat "$SC_API/CLAUDE.md")"
  run_cli_capture output "$SC_HUB" update
  run_cli_capture output "$SC_HUB" sync --apply
  assert_eq "$(cat "$SC_API/CLAUDE.md")" "$before"
  [[ ! -e "$SC_API/AGENTS.md" && ! -e "$SC_API/GEMINI.md" ]] || fail "sibling repo got generated entry files"
}

test_scope_file_with_another_value_changes_nothing() {
  local output
  setup_scope_fixture
  printf 'everything\n' > "$SC_HUB/.platform/sync-scope"
  run_cli_capture output "$SC_HUB" update
  [[ "$(repos_in_script)" == *"/ApiServer"* ]] || fail "only the exact value hub-only opts out"
}

test_update_lists_sibling_repos_by_default
test_hub_only_scope_keeps_siblings_out_across_updates
test_hub_only_scope_never_touches_the_siblings_entry_files
test_scope_file_with_another_value_changes_nothing
