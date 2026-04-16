#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_bootstrap_rejects_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  run_cli_capture output "$dir" bootstrap --bad-flag
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Usage: agentboard bootstrap [--apply-domains]"
}

test_bootstrap_seeds_placeholder_brief_from_single_stream() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/src/features/auth"
  printf '{}\n' > "$dir/package.json"
  printf 'export const auth = true;\n' > "$dir/src/features/auth/index.ts"
  init_project_fixture "$dir"

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

## Scope
Fix login failures in admin auth.

## Next action
Validate the hotfix against a real failure case.
EOF

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active workstreams

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| auth-fix | bug | active | codex | 2026-04-15 |
EOF

  run_cli_capture output "$dir" bootstrap
  assert_contains "$output" "Seeded work/BRIEF.md from the only active stream"
  assert_file_contains "$dir/.platform/work/BRIEF.md" '**Feature:** auth-fix'
}

test_bootstrap_rejects_unknown_flag
test_bootstrap_seeds_placeholder_brief_from_single_stream
