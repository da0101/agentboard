#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_doctor_fails_for_missing_stream_metadata() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  cat > "$dir/.platform/domains/auth.md" <<'EOF'
---
domain_id: dom-auth
slug: auth
status: active
repo_ids: [repo-primary]
related_domain_slugs: []
created_at: 2026-04-15
updated_at: 2026-04-15
---
EOF

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
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

  cat > "$dir/.platform/work/ACTIVE.md" <<'EOF'
# Active workstreams

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| auth-fix | bug | active | codex | 2026-04-15 |
EOF

  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Stream 'auth-fix' is missing frontmatter key 'stream_id'"
}

test_doctor_passes_for_valid_streams() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"

  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream auth-fix --domain auth --type bug --agent codex >/dev/null
  )

  run_cli_capture output "$dir" doctor
  assert_contains "$output" "Doctor passed"
}

test_doctor_warns_when_runtime_gitignore_missing() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  init_project_fixture "$dir"
  rm -f "$dir/.gitignore"

  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "runtime block"
}

test_doctor_fails_for_missing_stream_metadata
test_doctor_passes_for_valid_streams
test_doctor_warns_when_runtime_gitignore_missing
