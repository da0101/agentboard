#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_frontmatter_helpers() {
  local file
  file="$(mktemp)"
  cat > "$file" <<'EOF'
---
slug: auth-fix
repo_ids: [backend, frontend]
---
body
EOF

  assert_eq "$(frontmatter_value "$file" "slug")" "auth-fix"
  assert_eq "$(frontmatter_value "$file" "repo_ids")" "[backend, frontend]"
  assert_eq "$(inline_array_items "[backend, frontend]" | join_lines_comma)" "backend, frontend"
  assert_eq "$(printf 'backend\nfrontend\n' | frontmatter_inline_array)" "[backend, frontend]"
}

test_active_and_repo_registry_parsers() {
  local dir active repos
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"
  active="$dir/.platform/work/ACTIVE.md"
  repos="$dir/.platform/repos.md"

  cat > "$active" <<'EOF'
# Active

| Stream | Type | Status | Agent | Updated |
|---|---|---|---|---|
| auth-fix | bug | active | codex | 2026-04-15 |
| _(none)_ | — | — | — | — |

## Archive
EOF

  cat > "$repos" <<'EOF'
## Repos
| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| backend | `./backend api` | backend / fastapi | `backend.md` |
| frontend | `./frontend` | frontend / react | `frontend.md` |

## Notes
EOF

  assert_eq "$(stream_rows_from_active "$active")" "auth-fix|bug|active|codex|2026-04-15"
  assert_eq "$(repo_rows_from_registry "$repos" | wc -l | tr -d ' ')" "2"
  assert_eq "$(repo_row_for_id "$(repo_rows_from_registry "$repos")" "backend")" "backend|./backend api|backend / fastapi|backend.md"
}

test_path_and_placeholder_helpers() {
  local dir repos
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform" "$dir/backend api"
  repos="$dir/.platform/repos.md"
  : > "$repos"

  assert_eq "$(resolve_repo_path "$repos" "./backend api")" "$dir/backend api"
  assert_eq "$(slugify "Backend API v2")" "backend-api-v2"

  is_placeholder_value "—"
  is_placeholder_value "YYYY-MM-DD"
  if is_placeholder_value "backend"; then
    fail "backend should not be treated as a placeholder"
  fi
}

test_shell_helpers() {
  local old_path="$PATH"
  export PATH="/tmp/custom/bin:$old_path"

  assert_eq "$(detect_shell_name)" "zsh"
  assert_eq "$(shell_path_snippet "fish" "/tmp/custom/bin")" 'fish_add_path "/tmp/custom/bin"'
  path_contains_dir "/tmp/custom/bin"
}

test_frontmatter_helpers
test_active_and_repo_registry_parsers
test_path_and_placeholder_helpers
test_shell_helpers
