#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_repair_dry_run_reports_stale_role_paths_without_writing() {
  local dir output before
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Read .claude/roles/INDEX.md and .claude/roles/debugger.md' > "$dir/CLAUDE.md"
  before="$(cat "$dir/CLAUDE.md")"

  run_cli_capture output "$dir" repair --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Dry-run mode"
  assert_contains "$output" "CLAUDE.md contains stale .claude/roles path(s)"
  assert_eq "$(cat "$dir/CLAUDE.md")" "$before"
}

test_repair_rewrites_role_paths_and_refreshes_runtime_ignore() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Read .claude/roles/INDEX.md and .claude/roles/debugger.md' > "$dir/CLAUDE.md"

  run_cli_capture output "$dir" repair
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Repair passed"
  assert_file_contains "$dir/CLAUDE.md" ".platform/roles/INDEX.md"
  assert_file_contains "$dir/CLAUDE.md" ".platform/roles/debugger.md"
  assert_file_not_contains "$dir/CLAUDE.md" ".claude/roles"
  assert_file_contains "$dir/.gitignore" "agentboard.hud-status.json"
}

test_doctor_repair_delegates_to_repair() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  printf '%s\n' 'Role path: .claude/roles/product-manager.md' > "$dir/AGENTS.md"

  run_cli_capture output "$dir" doctor --repair --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "ab repair"
  assert_contains "$output" "AGENTS.md contains stale .claude/roles path(s)"
  assert_file_contains "$dir/AGENTS.md" ".claude/roles/product-manager.md"
}

test_repair_stream_metadata_and_stale_active_rows() {
  local dir output doctor_output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  cat > "$dir/.platform/domains/analytics.md" <<'EOF'
---
domain_id: dom-analytics
slug: analytics
status: active
repo_ids: [repo-primary]
related_domain_slugs: []
created_at: 2026-06-27
updated_at: 2026-06-27
---

# analytics
EOF

  cat > "$dir/.platform/work/analytics.md" <<'EOF'
---
slug: analytics
type: feature
status: in-progress
agent_owner: codex
domain_slugs: [analytics]
repo_ids: [repo-primary]
created_at: 2026-06-27
updated_at: 2026-06-27
closure_approved: false
---

# Analytics
EOF

  cat > "$dir/.platform/work/Status.md" <<'EOF'
---
stream_id: stream-app-store-pt-br
slug: Status
type: feature
status: in-progress
agent_owner: codex
domain_slugs: [analytics]
repo_ids: [repo-primary]
created_at: 2026-06-27
updated_at: 2026-06-27
closure_approved: false
---

# Status
EOF

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active Work

| Stream | Type | Status | Agent | Last updated |
|---|---|---|---|---|
| analytics | feature | in-progress | codex | 2026-06-27 |
| polish-release | feature | in-progress | codex | 2026-06-27 |
EOF

  cat > "$dir/.platform/work/BRIEF.md" <<'EOF'
# Feature Brief

**Feature:** broken
**Status:** in-progress
EOF

  run_cli_capture output "$dir" repair
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Repair passed"
  assert_file_contains "$dir/.platform/work/analytics.md" "stream_id: stream-analytics"
  assert_file_contains "$dir/.platform/work/Status.md" "stream_id: stream-Status"
  assert_file_not_contains "$dir/.platform/work/ACTIVE.md" "polish-release"
  assert_file_contains "$dir/.platform/work/BRIEF.md" '**Stream file:** `work/analytics.md`'

  run_cli_capture doctor_output "$dir" doctor --ci
  assert_status "$RUN_STATUS" 0
  assert_not_contains "$doctor_output" "missing frontmatter key 'stream_id'"
  assert_not_contains "$doctor_output" "non-canonical stream_id"
  assert_not_contains "$doctor_output" "missing file .platform/work/polish-release.md"
}

test_repair_dry_run_reports_stale_role_paths_without_writing
test_repair_rewrites_role_paths_and_refreshes_runtime_ignore
test_doctor_repair_delegates_to_repair
test_repair_stream_metadata_and_stale_active_rows
