#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

HOOK="$TEST_ROOT/templates/platform/scripts/hooks/platform-closure-gate.js"

test_hook_blocks_without_human_approval() {
  local dir input output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: false
---

## Done criteria
- [x] code complete
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  output="$(printf '%s' "$input" | node "$HOOK" 2>&1)"
  status=$?
  set -e

  assert_status "$status" 2
  assert_contains "$output" "closure_approved is not set to true"
}

test_hook_blocks_with_unchecked_done_criteria() {
  local dir input output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: true
---

## Done criteria
- [ ] manual QA
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  output="$(printf '%s' "$input" | node "$HOOK" 2>&1)"
  status=$?
  set -e

  assert_status "$status" 2
  assert_contains "$output" "Unchecked done criteria remain"
}

test_hook_allows_closure_when_approved_and_complete() {
  local dir input status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: true
---

## Done criteria
- [x] manual QA
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  printf '%s' "$input" | node "$HOOK" >/dev/null 2>&1
  status=$?
  set -e

  assert_status "$status" 0
}

test_hook_blocks_without_human_approval
test_hook_blocks_with_unchecked_done_criteria
test_hook_allows_closure_when_approved_and_complete
