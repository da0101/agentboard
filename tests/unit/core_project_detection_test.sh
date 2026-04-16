#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_detect_folder_kind_variants() {
  local empty_dir project_dir hub_dir
  empty_dir="$(mktemp -d)"
  project_dir="$(mktemp -d)"
  hub_dir="$(mktemp -d)"

  printf '# readme\n' > "$empty_dir/README.md"
  printf '{}' > "$project_dir/package.json"
  mkdir -p "$hub_dir/backend" "$hub_dir/frontend"
  printf '{}' > "$hub_dir/backend/package.json"
  printf '{}' > "$hub_dir/frontend/package.json"

  assert_eq "$(detect_folder_kind "$empty_dir")" "empty"
  assert_eq "$(detect_folder_kind "$project_dir")" "project"
  assert_eq "$(detect_folder_kind "$hub_dir")" "hub-candidate"
}

test_write_brief_stub_and_skill_description() {
  local dir brief skill
  dir="$(mktemp -d)"
  brief="$dir/BRIEF.md"
  skill="$dir/SKILL.md"

  write_brief_stub "$brief" "agentboard" "auth-fix" $'auth\nbackend-auth' "planning"
  assert_file_contains "$brief" '**Feature:** auth-fix'
  assert_file_contains "$brief" '.platform/domains/auth.md'
  assert_file_contains "$brief" '.platform/domains/backend-auth.md'

  cat > "$skill" <<'EOF'
---
description: "This is the first sentence. This is extra detail that should be trimmed."
---
EOF
  assert_eq "$(skill_description "$skill")" "This is the first sentence"
}

test_detect_folder_kind_variants
test_write_brief_stub_and_skill_description
