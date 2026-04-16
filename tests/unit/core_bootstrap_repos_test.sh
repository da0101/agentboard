#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_repo_role_and_stack_hint_detection() {
  local fastapi_dir unknown_dir
  fastapi_dir="$(mktemp -d)"
  unknown_dir="$(mktemp -d)"

  cat > "$fastapi_dir/pyproject.toml" <<'EOF'
[project]
name = "api"
dependencies = ["fastapi", "uvicorn"]
EOF

  mkdir -p "$unknown_dir/scripts"
  printf '#!/usr/bin/env bash\necho ok\n' > "$unknown_dir/scripts/helper.sh"

  assert_eq "$(detect_repo_role "$fastapi_dir" "backend-api")" "backend"
  assert_eq "$(detect_repo_stack_hint "$fastapi_dir" "backend-api" "backend")" "fastapi"
  assert_eq "$(detect_repo_role "$unknown_dir" "helpers")" "unknown"
}

test_repo_bootstrap_commands_and_relationships() {
  local node_dir backend_dir frontend_dir discovered commands
  node_dir="$(mktemp -d)"
  backend_dir="$(mktemp -d)"
  frontend_dir="$(mktemp -d)"

  cat > "$node_dir/package.json" <<'EOF'
{
  "name": "api-service",
  "scripts": {
    "dev": "node src/server.js",
    "test": "vitest",
    "build": "tsup src/server.ts"
  }
}
EOF
  : > "$node_dir/yarn.lock"
  mkdir -p "$node_dir/src"
  printf 'console.log("ok")\n' > "$node_dir/src/server.js"

  cat > "$backend_dir/manage.py" <<'EOF'
print("ok")
EOF
  cat > "$frontend_dir/package.json" <<'EOF'
{
  "name": "web",
  "dependencies": {
    "react": "^19.0.0"
  }
}
EOF

  commands="$(repo_bootstrap_commands "$node_dir" "backend" "node-service")"
  assert_eq "$commands" "yarn run dev|yarn test|yarn run build"

  discovered="$(printf 'backend|./backend|backend / django|backend.md|%s|backend\nfrontend|./frontend|frontend / react|frontend.md|%s|frontend\n' "$backend_dir" "$frontend_dir")"
  assert_contains "$(repo_relationship_lines "backend" "$backend_dir" "$discovered")" 'Likely serves APIs, auth, or shared contracts to `frontend`'
}

test_repo_boundaries_and_artifacts() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/src" "$dir/tests" "$dir/docs"
  printf '{}' > "$dir/package.json"
  printf '# Readme\n' > "$dir/README.md"
  printf 'openapi: 3.0.0\n' > "$dir/openapi.yaml"

  assert_contains "$(repo_boundary_lines "$dir" "src")" '`tests/`'
  assert_contains "$(repo_context_artifact_lines "$dir")" '`README.md`'
  assert_contains "$(repo_context_artifact_lines "$dir")" '`openapi.yaml`'
}

test_repo_role_and_stack_hint_detection
test_repo_bootstrap_commands_and_relationships
test_repo_boundaries_and_artifacts
