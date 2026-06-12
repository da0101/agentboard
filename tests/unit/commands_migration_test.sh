#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_migrate_preview_leaves_legacy_files_untouched() {
  local dir output before
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  cat > "$dir/.platform/work/legacy-auth.md" <<'EOF'
# Legacy Auth
**Type:** bug
**Status:** active
**Agent:** codex
**Started:** 2026-04-15

## Backend
- backend auth API
EOF

  cat > "$dir/.platform/domains/auth.md" <<'EOF'
# Domain: Auth

## Backend
- backend auth service
EOF

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active workstreams

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| legacy-auth | bug | active | codex | 2026-04-15 |
EOF

  before="$(cat "$dir/.platform/work/legacy-auth.md")"
  run_cli_capture output "$dir" migrate
  assert_contains "$output" "would migrate stream 'legacy-auth'"
  assert_eq "$(cat "$dir/.platform/work/legacy-auth.md")" "$before"
}

test_brief_upgrade_requires_slug_when_multiple_streams_exist() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active workstreams

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| auth-fix | bug | active | codex | 2026-04-15 |
| billing-fix | bug | active | claude | 2026-04-15 |
EOF

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
stream_id: stream-auth-fix
slug: auth-fix
type: bug
status: active
agent_owner: codex
domain_slugs: [auth]
repo_ids: [repo-primary]
created_at: 2026-04-15
updated_at: 2026-04-15
closure_approved: false
---
EOF
  cp "$dir/.platform/work/auth-fix.md" "$dir/.platform/work/billing-fix.md"

  run_cli_capture output "$dir" brief-upgrade
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "brief-upgrade needs a target stream when more than one stream is active."
  assert_contains "$output" "Active streams:"
}

test_migrate_apply_writes_frontmatter_to_legacy_stream() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  cat > "$dir/.platform/domains/auth.md" <<'EOF'
# Domain: Auth

## Backend
- backend auth service
EOF

  cat > "$dir/.platform/work/legacy-auth.md" <<'EOF'
# Legacy Auth
**Type:** bug
**Status:** active
**Agent:** codex
**Started:** 2026-04-01

## Backend
- backend auth API
EOF

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active workstreams

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| legacy-auth | bug | active | codex | 2026-04-01 |
EOF

  run_cli_capture output "$dir" migrate --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Migrated legacy stream"
  assert_file_contains "$dir/.platform/work/legacy-auth.md" "stream_id:"
  assert_file_contains "$dir/.platform/work/legacy-auth.md" "slug: legacy-auth"
  assert_file_contains "$dir/.platform/work/legacy-auth.md" "closure_approved:"
  assert_file_contains "$dir/.platform/work/legacy-auth.md" "# Legacy Auth"
}

test_migrate_preview_leaves_legacy_files_untouched
test_brief_upgrade_requires_slug_when_multiple_streams_exist
test_migrate_apply_writes_frontmatter_to_legacy_stream
