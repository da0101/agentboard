#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1
HOOK="$TEST_ROOT/lib/agentboard/hooks/hub-route.sh"

# A hub with two sibling repos; the registry is written by the real `ab hub register`.
setup_hub_fixture() {
  HB="$(mktemp -d)"; HB="$(cd "$HB" && pwd -P)"
  HUB="$HB/hub"; API="$HB/ApiServer"; WEB="$HB/web-app"
  mkdir -p "$HUB" "$API/src" "$WEB/.claude"
  printf '# api team\n' > "$API/CLAUDE.md"; printf '# web\n' > "$WEB/AGENTS.md"
  make_git_repo "$API" main; commit_all "$API" initial
  printf '{}\n' > "$HUB/package.json"; make_git_repo "$HUB" main; commit_all "$HUB" initial
  init_project_fixture "$HUB"
  cat > "$HUB/.platform/repos.md" <<'EOT'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
| web-app | ../web-app | React | web.md |
| ghost | ../does-not-exist | none | ghost.md |
EOT
  export AB_HUBS_FILE="$HB/hubs.tsv"
  run_cli_capture OUT "$HUB" hub register
}

# hook <mode> <json> — runs the hook, sets HOOK_RC and HOOK_OUT (stdout+stderr)
hook() {
  local mode="$1" json="$2" tmp; tmp="$(mktemp)"
  set +e; printf '%s' "$json" | bash "$HOOK" "$mode" > "$tmp" 2>&1; HOOK_RC=$?; set -e
  HOOK_OUT="$(cat "$tmp")"; rm -f "$tmp"
}

edit_json() { printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"; }
bash_json() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

test_register_records_existing_repos_only_and_is_idempotent() {
  setup_hub_fixture
  assert_contains "$OUT" "api-server"; assert_contains "$OUT" "web-app"; assert_not_contains "$OUT" "ghost"
  run_cli_capture OUT "$HUB" hub register
  [[ "$(grep -c . "$AB_HUBS_FILE")" == 2 ]] || fail "re-registering must replace, not duplicate"
  assert_file_contains "$AB_HUBS_FILE" "$API"
  run_cli_capture OUT "$HUB" hub unregister
  [[ ! -s "$AB_HUBS_FILE" ]] || fail "unregister should empty this hub's rows"
}

test_session_hook_prints_hub_context_inside_a_registered_repo() {
  setup_hub_fixture
  hook session "{\"cwd\":\"$API/src\"}"
  assert_status "$HOOK_RC" 0
  assert_contains "$HOOK_OUT" "part of the platform hub at $HUB"
  assert_contains "$HOOK_OUT" "NEVER create or edit CLAUDE.md"
}

test_session_hook_is_silent_elsewhere_and_without_a_registry() {
  setup_hub_fixture
  hook session "{\"cwd\":\"$HB\"}";  assert_eq "$HOOK_OUT" ""
  hook session "{\"cwd\":\"$HUB\"}"; assert_eq "$HOOK_OUT" ""
  AB_HUBS_FILE="$HB/none.tsv" hook session "{\"cwd\":\"$API\"}"; assert_eq "$HOOK_OUT" ""
}

test_guard_blocks_entry_files_in_registered_repos() {
  local f
  setup_hub_fixture
  for f in "$API/CLAUDE.md" "$API/AGENTS.md" "$API/src/CLAUDE.md" "$WEB/GEMINI.md" "$WEB/.claude/settings.json" "$WEB/.claude/rules/x.md"; do
    for tool in Write Edit MultiEdit; do
      hook guard "$(edit_json "$tool" "$API" "$f")"
      assert_status "$HOOK_RC" 2
    done
  done
  assert_contains "$HOOK_OUT" "Blocked by Agentboard"; assert_contains "$HOOK_OUT" "$HUB"
}

test_guard_resolves_relative_paths_and_dotdot_against_cwd() {
  setup_hub_fixture
  hook guard "$(edit_json Edit "$API/src" "../CLAUDE.md")"; assert_status "$HOOK_RC" 2
  hook guard "$(edit_json Edit "$API" "src/../AGENTS.md")"; assert_status "$HOOK_RC" 2
}

test_guard_allows_ordinary_files_and_other_projects() {
  setup_hub_fixture
  hook guard "$(edit_json Write "$API" "$API/src/app.py")"; assert_status "$HOOK_RC" 0
  hook guard "$(edit_json Write "$API" "$API/README.md")"; assert_status "$HOOK_RC" 0
  hook guard "$(edit_json Write "$HUB" "$HUB/CLAUDE.md")"; assert_status "$HOOK_RC" 0   # the hub is yours
  hook guard "$(edit_json Write "$HB" "$HB/elsewhere/CLAUDE.md")"; assert_status "$HOOK_RC" 0
  hook guard '{"tool_name":"Read","cwd":"/","tool_input":{"file_path":"/x/CLAUDE.md"}}'; assert_status "$HOOK_RC" 0
}

test_guard_does_not_mistake_a_name_prefix_for_the_repo() {
  setup_hub_fixture
  mkdir -p "$HB/ApiServer-old"
  hook guard "$(edit_json Write "$HB" "$HB/ApiServer-old/CLAUDE.md")"; assert_status "$HOOK_RC" 0
}

test_guard_blocks_codex_apply_patch_paths() {
  setup_hub_fixture
  hook guard "{\"tool_name\":\"apply_patch\",\"cwd\":\"$API\",\"tool_input\":{\"command\":\"*** Begin Patch\\n*** Update File: CLAUDE.md\\n@@\\n-a\\n+b\\n*** End Patch\"}}"
  assert_status "$HOOK_RC" 2
  hook guard "{\"tool_name\":\"apply_patch\",\"cwd\":\"$API\",\"tool_input\":{\"command\":\"*** Begin Patch\\n*** Add File: src/new.py\\n+x\\n*** End Patch\"}}"
  assert_status "$HOOK_RC" 0
}

test_guard_blocks_shell_writes_but_not_reads() {
  local c
  setup_hub_fixture
  for c in "echo hi >> CLAUDE.md" "echo hi > AGENTS.md" "printf x | tee GEMINI.md" "sed -i '' s/a/b/ CLAUDE.md" "rm CLAUDE.md" "mv AGENTS.md /tmp/x" "echo x > .claude/settings.json"; do
    hook guard "$(bash_json "$API" "$c")"; [[ "$HOOK_RC" == 2 ]] || fail "should block shell: $c"
  done
  for c in "cat CLAUDE.md" "grep -n foo CLAUDE.md" "git status" "cat CLAUDE.md > /tmp/copy.txt" "ls -la"; do
    hook guard "$(bash_json "$API" "$c")"; [[ "$HOOK_RC" == 0 ]] || fail "should allow shell: $c"
  done
}

test_override_variable_lifts_the_guard() {
  setup_hub_fixture
  AB_ALLOW_ENTRY_EDIT=1 hook guard "$(edit_json Write "$API" "$API/CLAUDE.md")"
  assert_status "$HOOK_RC" 0
}

test_guard_fails_open_on_garbage_input() {
  setup_hub_fixture
  hook guard 'not json at all'; assert_status "$HOOK_RC" 0
  hook guard ''; assert_status "$HOOK_RC" 0
}

test_hub_check_reports_what_the_hooks_do() {
  setup_hub_fixture
  run_cli_capture OUT "$API" hub check
  assert_contains "$OUT" "CLAUDE.md"; assert_contains "$OUT" "BLOCKED"
  run_cli_capture OUT "$HB" hub check
  assert_contains "$OUT" "not inside a registered repo"
}

test_register_registers_repos_and_never_writes_into_them() {
  setup_hub_fixture
  git -C "$API" status --porcelain > "$HB/before.txt"
  run_cli_capture OUT "$HUB" hub register
  git -C "$API" status --porcelain > "$HB/after.txt"
  cmp -s "$HB/before.txt" "$HB/after.txt" || fail "register must not change the sibling repo"
  [[ ! -e "$API/.claude" && ! -e "$API/.platform" ]] || fail "nothing may be added to the sibling repo"
}

test_register_records_existing_repos_only_and_is_idempotent
test_session_hook_prints_hub_context_inside_a_registered_repo
test_session_hook_is_silent_elsewhere_and_without_a_registry
test_guard_blocks_entry_files_in_registered_repos
test_guard_resolves_relative_paths_and_dotdot_against_cwd
test_guard_allows_ordinary_files_and_other_projects
test_guard_does_not_mistake_a_name_prefix_for_the_repo
test_guard_blocks_codex_apply_patch_paths
test_guard_blocks_shell_writes_but_not_reads
test_override_variable_lifts_the_guard
test_guard_fails_open_on_garbage_input
test_hub_check_reports_what_the_hooks_do
test_register_registers_repos_and_never_writes_into_them
