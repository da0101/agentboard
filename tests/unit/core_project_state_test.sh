#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_canonical_ids_and_file_enumeration() {
  local dir files
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work" "$dir/.platform/domains"
  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
stream_id: stream-auth-fix
---
EOF
  : > "$dir/.platform/work/ACTIVE.md"
  : > "$dir/.platform/work/BRIEF.md"
  : > "$dir/.platform/work/TEMPLATE.md"
  cat > "$dir/.platform/domains/auth.md" <<'EOF'
---
domain_id: dom-auth
---
EOF
  : > "$dir/.platform/domains/TEMPLATE.md"

  (
    cd "$dir"
    assert_eq "$(canonical_stream_id "auth-fix")" "stream-auth-fix"
    assert_eq "$(canonical_domain_id "auth")" "dom-auth"
    files="$(stream_files)"
    assert_contains "$files" ".platform/work/auth-fix.md"
    assert_not_contains "$files" "ACTIVE.md"
    assert_eq "$(domain_files)" "./.platform/domains/auth.md"
  )
}

test_repo_table_and_sync_script_updates() {
  local dir repos sync
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/scripts"
  repos="$dir/.platform/repos.md"
  sync="$dir/.platform/scripts/sync-context.sh"

  cat > "$repos" <<'EOF'
## Repos
| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| _repo-a_ | `../repo-a` | _stack_ | `repo-a.md` |

## Notes
EOF

  cat > "$sync" <<'EOF'
#!/usr/bin/env bash
REPOS=(
  "old"
)
EOF

  replace_repos_table "$repos" $'| Repo ID | Path | Stack | Deep reference |\n|---|---|---|---|\n| backend | `./backend` | backend / django | `backend.md` |\n'
  write_sync_repos_array "$sync" $'/tmp/backend\n/tmp/frontend\n'

  assert_file_contains "$repos" '| backend | `./backend` | backend / django | `backend.md` |'
  assert_file_contains "$sync" '"/tmp/backend"'
  assert_file_contains "$sync" '"/tmp/frontend"'
}

test_render_brief_from_stream_includes_context() {
  local dir stream repos rendered
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work" "$dir/.platform/domains"
  repos="$dir/.platform/repos.md"
  stream="$dir/.platform/work/auth-fix.md"

  cat > "$repos" <<'EOF'
## Repos
| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| backend | `./backend` | backend / django | `backend.md` |
EOF

  cat > "$stream" <<'EOF'
---
stream_id: stream-auth-fix
slug: auth-fix
type: bug
status: active
agent_owner: codex
domain_slugs: [auth]
repo_ids: [backend]
created_at: 2026-04-15
updated_at: 2026-04-15
closure_approved: false
---

## Scope
Fix auth failures in the admin API.

## Why
Logins are failing for staff users.

## Done criteria
- [x] auth endpoint fixed
- [ ] manual QA

## Key decisions
- 2026-04-15 — keep the existing token format

## Next action
Verify the patched login flow against staging data.
EOF

  rendered="$(render_brief_from_stream "agentboard" "auth-fix" "active" "$stream" "$repos")"
  assert_contains "$rendered" 'Fix auth failures in the admin API.'
  assert_contains "$rendered" 'Verify the patched login flow against staging data.'
  assert_contains "$rendered" '.platform/backend.md'
  assert_contains "$rendered" '.platform/domains/auth.md'
}

test_canonical_ids_and_file_enumeration
test_repo_table_and_sync_script_updates
test_render_brief_from_stream_includes_context
