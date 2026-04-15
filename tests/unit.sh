#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/agentboard"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2"
  [[ "$actual" == "$expected" ]] || fail "expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

make_git_repo() {
  local dir="$1"
  git -C "$dir" init -b main >/dev/null 2>&1
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
}

test_detect_repo_role_and_hint() {
  local dir
  dir="$(mktemp -d)"

  mkdir -p "$dir/frontend/src"
  printf '{\n  "name": "frontend",\n  "dependencies": { "react": "^19.0.0" }\n}\n' > "$dir/frontend/package.json"
  assert_eq "$(detect_repo_role "$dir/frontend" "frontend")" "frontend"
  assert_eq "$(detect_repo_stack_hint "$dir/frontend" "frontend" "frontend")" "react"

  mkdir -p "$dir/backend/src"
  printf '{\n  "name": "backend",\n  "dependencies": { "express": "^5.0.0" }\n}\n' > "$dir/backend/package.json"
  assert_eq "$(detect_repo_role "$dir/backend" "backend")" "backend"
  assert_eq "$(detect_repo_stack_hint "$dir/backend" "backend" "backend")" "node-service"

  mkdir -p "$dir/mobile/App.xcodeproj" "$dir/mobile/ios"
  printf '// placeholder\n' > "$dir/mobile/App.xcodeproj/project.pbxproj"
  assert_eq "$(detect_repo_role "$dir/mobile" "mobile")" "mobile"
  assert_eq "$(detect_repo_stack_hint "$dir/mobile" "mobile" "mobile")" "ios"

  mkdir -p "$dir/unknown/scripts"
  printf '#!/usr/bin/env bash\necho ok\n' > "$dir/unknown/scripts/helper.sh"
  assert_eq "$(detect_repo_role "$dir/unknown" "unknown")" "unknown"
  assert_eq "$(detect_repo_stack_hint "$dir/unknown" "unknown" "unknown")" ""
}

test_infer_stream_type_from_diff() {
  assert_eq "$(infer_stream_type_from_diff "" "src/auth/errors.ts" "")" "bug"
  assert_eq "$(infer_stream_type_from_diff "chore-cleanup" "" "")" "improvement"
  assert_eq "$(infer_stream_type_from_diff "feat-auth" "" "")" "feature"
}

test_repo_diff_signal_text_ignores_platform_files() {
  local dir signals
  dir="$(mktemp -d)"
  mkdir -p "$dir/src" "$dir/.platform/work"
  printf 'console.log("ok");\n' > "$dir/src/index.js"
  printf '%s\n' '---' 'closure_approved: false' '---' > "$dir/.platform/work/demo.md"
  make_git_repo "$dir"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1

  printf 'console.log("changed");\n' > "$dir/src/index.js"
  printf '%s\n' '---' 'closure_approved: true' '---' > "$dir/.platform/work/demo.md"
  signals="$(repo_diff_signal_text "$dir")"

  assert_contains "$signals" 'console.log'
  [[ "$signals" != *"closure_approved"* ]] || fail "expected .platform diffs to be filtered"
}

test_closure_gate_blocks_unapproved_or_incomplete_streams() {
  local dir payload output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"
  cat > "$dir/.platform/work/demo.md" <<'EOF'
---
closure_approved: false
---

# demo

## Done criteria
- [ ] manual verification
EOF
  payload='{"tool_name":"Edit","cwd":"'"$dir"'","tool_input":{"file_path":"'"$dir"'/.platform/work/ACTIVE.md","old_string":"| demo | feature | active | codex |\n","new_string":""}}'
  set +e
  output="$(printf '%s' "$payload" | node "$ROOT/templates/platform/scripts/hooks/platform-closure-gate.js")"
  status=$?
  set -e

  [[ $status -eq 2 ]] || fail "expected closure gate to block unapproved stream"
  assert_contains "$output" "closure_approved is not set to true"
}

test_closure_gate_allows_approved_complete_streams() {
  local dir payload status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"
  cat > "$dir/.platform/work/demo.md" <<'EOF'
---
closure_approved: true
---

# demo

## Done criteria
- [x] tests pass
- [x] manual verification
EOF
  payload='{"tool_name":"Edit","cwd":"'"$dir"'","tool_input":{"file_path":"'"$dir"'/.platform/work/ACTIVE.md","old_string":"| demo | feature | active | codex |\n","new_string":""}}'
  set +e
  printf '%s' "$payload" | node "$ROOT/templates/platform/scripts/hooks/platform-closure-gate.js" >/tmp/agentboard-closure-gate.out
  status=$?
  set -e

  [[ $status -eq 0 ]] || fail "expected closure gate to allow approved complete stream"
}

test_closure_gate_blocks_incomplete_streams_even_if_approved() {
  local dir payload output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"
  cat > "$dir/.platform/work/demo.md" <<'EOF'
---
closure_approved: true
---

# demo

## Done criteria
- [x] tests pass
- [ ] manual verification
EOF
  payload='{"tool_name":"Edit","cwd":"'"$dir"'","tool_input":{"file_path":"'"$dir"'/.platform/work/ACTIVE.md","old_string":"| demo | feature | active | codex |\n","new_string":""}}'
  set +e
  output="$(printf '%s' "$payload" | node "$ROOT/templates/platform/scripts/hooks/platform-closure-gate.js")"
  status=$?
  set -e

  [[ $status -eq 2 ]] || fail "expected closure gate to block incomplete approved stream"
  assert_contains "$output" "Unchecked done criteria remain"
}

test_detect_repo_role_and_hint
test_infer_stream_type_from_diff
test_repo_diff_signal_text_ignores_platform_files
test_closure_gate_blocks_unapproved_or_incomplete_streams
test_closure_gate_allows_approved_complete_streams
test_closure_gate_blocks_incomplete_streams_even_if_approved

printf 'PASS: unit\n'
