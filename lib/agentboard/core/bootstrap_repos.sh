package_json_has_script() {
  local package_json="$1" script_name="$2"
  [[ -f "$package_json" ]] || return 1
  grep -Eq "\"${script_name}\"[[:space:]]*:" "$package_json"
}

package_json_matches() {
  local package_json="$1" pattern="$2"
  [[ -f "$package_json" ]] || return 1
  grep -Eiq "$pattern" "$package_json"
}

node_package_runner() {
  local repo_path="$1"
  if [[ -f "$repo_path/pnpm-lock.yaml" ]]; then
    printf '%s\n' "pnpm"
  elif [[ -f "$repo_path/yarn.lock" ]]; then
    printf '%s\n' "yarn"
  elif [[ -f "$repo_path/bun.lockb" || -f "$repo_path/bun.lock" ]]; then
    printf '%s\n' "bun"
  else
    printf '%s\n' "npm"
  fi
}

repo_id_matches() {
  local repo_id="$1" pattern="$2"
  printf '%s' "$(slugify "$repo_id")" | grep -Eq "(^|-)(${pattern})(-|$)"
}

detect_repo_role() {
  local repo_path="$1" repo_id="${2:-}"
  local package_json="$repo_path/package.json"

  if [[ -d "$repo_path/terraform" || -d "$repo_path/charts" || -d "$repo_path/k8s" || -f "$repo_path/main.tf" || -f "$repo_path/docker-compose.yml" || -f "$repo_path/docker-compose.yaml" ]]; then
    printf '%s\n' "infra"
  elif [[ -f "$repo_path/pubspec.yaml" || -f "$repo_path/Podfile" || -f "$repo_path/build.gradle" || -f "$repo_path/build.gradle.kts" ]] \
    || compgen -G "$repo_path/*.xcodeproj" >/dev/null \
    || [[ -f "$repo_path/app/src/main/AndroidManifest.xml" ]]; then
    printf '%s\n' "mobile"
  elif [[ -f "$repo_path/firebase.json" && ( -d "$repo_path/functions" || -f "$repo_path/functions/package.json" ) ]]; then
    printf '%s\n' "backend"
  elif [[ -f "$repo_path/manage.py" || -f "$repo_path/go.mod" || -f "$repo_path/Cargo.toml" ]]; then
    printf '%s\n' "backend"
  elif [[ -f "$repo_path/pyproject.toml" || -f "$repo_path/requirements.txt" ]]; then
    if grep -Eiq 'fastapi|flask|django|starlette|uvicorn|gunicorn' "$repo_path/pyproject.toml" "$repo_path/requirements.txt" 2>/dev/null; then
      printf '%s\n' "backend"
    elif repo_id_matches "$repo_id" 'backend|api|server|worker|jobs?|functions?' || [[ -d "$repo_path/api" || -d "$repo_path/server" ]]; then
      printf '%s\n' "backend"
    else
      printf '%s\n' "unknown"
    fi
  elif [[ -f "$repo_path/angular.json" || -f "$repo_path/next.config.js" || -f "$repo_path/next.config.mjs" || -f "$repo_path/next.config.ts" \
    || -f "$repo_path/vite.config.ts" || -f "$repo_path/vite.config.js" || -f "$repo_path/vite.config.mjs" || -f "$repo_path/vite.config.cjs" ]]; then
    printf '%s\n' "frontend"
  elif [[ -f "$package_json" ]]; then
    if package_json_matches "$package_json" '"(express|fastify|koa|hono|nest|firebase-functions|@nestjs|apollo-server|trpc)"'; then
      printf '%s\n' "backend"
    elif package_json_matches "$package_json" '"(react|next|vue|nuxt|svelte|solid-js|@angular/core|gatsby)"' || [[ -f "$repo_path/index.html" ]]; then
      printf '%s\n' "frontend"
    elif repo_id_matches "$repo_id" 'shared|sdk|contracts?|types?|common|design-system|ui-kit'; then
      printf '%s\n' "shared"
    elif repo_id_matches "$repo_id" 'backend|api|server|worker|jobs?|functions?'; then
      printf '%s\n' "backend"
    elif repo_id_matches "$repo_id" 'frontend|web|site|admin|dashboard|console|client'; then
      printf '%s\n' "frontend"
    else
      printf '%s\n' "unknown"
    fi
  elif [[ -f "$repo_path/ProjectSettings/ProjectVersion.txt" || -d "$repo_path/Assets" ]]; then
    printf '%s\n' "unknown"
  elif repo_id_matches "$repo_id" 'mobile|ios|android'; then
    printf '%s\n' "mobile"
  elif repo_id_matches "$repo_id" 'backend|api|server|worker|jobs?|functions?'; then
    printf '%s\n' "backend"
  elif repo_id_matches "$repo_id" 'frontend|web|site|admin|dashboard|console|client'; then
    printf '%s\n' "frontend"
  elif repo_id_matches "$repo_id" 'shared|sdk|contracts?|types?|common|design-system|ui-kit'; then
    printf '%s\n' "shared"
  elif repo_id_matches "$repo_id" 'infra|ops|platform|deploy|devops'; then
    printf '%s\n' "infra"
  else
    printf '%s\n' "unknown"
  fi
}

detect_repo_stack_hint() {
  local repo_path="$1" repo_id="${2:-}" role="${3:-unknown}"
  local package_json="$repo_path/package.json"

  if [[ -f "$repo_path/firebase.json" && ( -d "$repo_path/functions" || -f "$repo_path/functions/package.json" ) ]] || package_json_matches "$package_json" '"firebase-functions"'; then
    printf '%s\n' "serverless-functions"
  elif [[ -f "$repo_path/manage.py" ]] || grep -Eiq 'django' "$repo_path/pyproject.toml" "$repo_path/requirements.txt" 2>/dev/null; then
    printf '%s\n' "django"
  elif grep -Eiq 'fastapi|starlette|uvicorn' "$repo_path/pyproject.toml" "$repo_path/requirements.txt" 2>/dev/null; then
    printf '%s\n' "fastapi"
  elif [[ -f "$repo_path/pubspec.yaml" ]]; then
    printf '%s\n' "flutter"
  elif compgen -G "$repo_path/*.xcodeproj" >/dev/null || [[ -f "$repo_path/Podfile" ]]; then
    printf '%s\n' "ios"
  elif [[ -f "$repo_path/build.gradle" || -f "$repo_path/build.gradle.kts" || -f "$repo_path/app/src/main/AndroidManifest.xml" ]]; then
    printf '%s\n' "android"
  elif [[ -f "$repo_path/ProjectSettings/ProjectVersion.txt" || -d "$repo_path/Assets" ]]; then
    printf '%s\n' "unity"
  elif [[ -f "$repo_path/go.mod" ]]; then
    printf '%s\n' "go"
  elif [[ -f "$repo_path/Cargo.toml" ]]; then
    printf '%s\n' "rust"
  elif [[ -f "$repo_path/angular.json" ]] || package_json_matches "$package_json" '"@angular/core"'; then
    printf '%s\n' "angular"
  elif package_json_matches "$package_json" '"next"'; then
    printf '%s\n' "nextjs"
  elif package_json_matches "$package_json" '"react"'; then
    if [[ -f "$repo_path/vite.config.ts" || -f "$repo_path/vite.config.js" || -f "$repo_path/vite.config.mjs" || -f "$repo_path/vite.config.cjs" ]]; then
      printf '%s\n' "react-vite"
    else
      printf '%s\n' "react"
    fi
  elif package_json_matches "$package_json" '"vue"'; then
    printf '%s\n' "vue"
  elif package_json_matches "$package_json" '"svelte"'; then
    printf '%s\n' "svelte"
  elif [[ -f "$package_json" && "$role" == "backend" ]]; then
    printf '%s\n' "node-service"
  elif [[ -f "$package_json" && "$role" == "shared" ]]; then
    printf '%s\n' "node-package"
  elif [[ "$role" == "infra" ]]; then
    printf '%s\n' "infrastructure"
  elif [[ "$role" == "backend" && ( -f "$repo_path/pyproject.toml" || -f "$repo_path/requirements.txt" ) ]]; then
    printf '%s\n' "python-service"
  else
    printf '%s\n' ""
  fi
}

format_repo_stack() {
  local role="$1" hint="$2"
  if [[ -n "$hint" ]]; then
    printf '%s / %s\n' "$role" "$hint"
  else
    printf '%s\n' "$role"
  fi
}

repo_bootstrap_commands() {
  local repo_path="$1" role="${2:-unknown}" hint="${3:-}"
  local package_json="$repo_path/package.json"
  local runner
  local dev="_fill during activation_" test="_fill during activation_" build="_fill during activation_"
  if [[ -f "$repo_path/manage.py" ]]; then
    dev="python manage.py runserver"
    if [[ -f "$repo_path/pytest.ini" || -d "$repo_path/tests" ]] || compgen -G "$repo_path/*/tests" >/dev/null; then
      test="pytest"
    else
      test="python manage.py test"
    fi
    build="python manage.py check"
  elif [[ "$hint" == "fastapi" ]]; then
    if [[ -f "$repo_path/app/main.py" ]]; then
      dev="uvicorn app.main:app --reload"
    elif [[ -f "$repo_path/main.py" ]]; then
      dev="uvicorn main:app --reload"
    fi
    if [[ -f "$repo_path/pytest.ini" || -d "$repo_path/tests" ]]; then
      test="pytest"
    fi
  elif [[ -f "$repo_path/pubspec.yaml" ]]; then
    dev="flutter run"
    test="flutter test"
    build="flutter build <target>"
  elif [[ -f "$repo_path/Cargo.toml" ]]; then
    dev="cargo run"
    test="cargo test"
    build="cargo build"
  elif [[ -f "$repo_path/go.mod" ]]; then
    dev="go run ./..."
    test="go test ./..."
    build="go build ./..."
  elif [[ -f "$package_json" ]]; then
    runner="$(node_package_runner "$repo_path")"
    if package_json_has_script "$package_json" "dev"; then dev="${runner} run dev"
    elif package_json_has_script "$package_json" "start"; then
      if [[ "$runner" == "npm" ]]; then
        dev="npm start"
      else
        dev="${runner} start"
      fi
    fi
    if package_json_has_script "$package_json" "test"; then
      if [[ "$runner" == "npm" ]]; then
        test="npm test"
      else
        test="${runner} test"
      fi
    elif package_json_has_script "$package_json" "test:unit"; then test="${runner} run test:unit"
    fi
    if package_json_has_script "$package_json" "build"; then build="${runner} run build"
    fi
  elif [[ "$hint" == "android" && -f "$repo_path/gradlew" ]]; then
    test="./gradlew test"
    build="./gradlew assembleDebug"
  elif [[ "$hint" == "ios" ]]; then
    test="xcodebuild test -scheme <fill>"
    build="xcodebuild build -scheme <fill>"
  elif [[ "$hint" == "infrastructure" ]]; then
    dev="terraform plan"
    test="terraform validate"
  elif [[ -f "$repo_path/Makefile" ]]; then
    dev="make dev"
    test="make test"
    build="make build"
  fi
  printf '%s|%s|%s\n' "$dev" "$test" "$build"
  return 0
}

repo_entrypoint_lines() {
  local repo_path="$1"
  local lines=""
  local entry
  for entry in \
    "manage.py" \
    "app/main.py" \
    "main.py" \
    "main.go" \
    "cmd/" \
    "src/main.ts" \
    "src/main.tsx" \
    "src/index.ts" \
    "src/index.tsx" \
    "src/index.js" \
    "src/index.jsx" \
    "server.js" \
    "server.ts" \
    "lib/main.dart" \
    "functions/src/index.ts" \
    "functions/src/index.js" \
    "functions/index.ts" \
    "functions/index.js" \
    "app/src/main/AndroidManifest.xml" \
    "Assets/" \
    "ProjectSettings/"; do
    if [[ "$entry" == */ ]]; then
      [[ -e "$repo_path/${entry%/}" ]] || continue
    else
      [[ -e "$repo_path/$entry" ]] || continue
    fi
    lines="${lines}- \`${entry}\`"$'\n'
  done
  for entry in "$repo_path"/*.xcodeproj; do
    [[ -e "$entry" ]] || continue
    lines="${lines}- \`$(basename "$entry")\`"$'\n'
  done
  [[ -n "$lines" ]] || lines="- _No clear entrypoint inferred during bootstrap._"$'\n'
  printf '%s' "$lines"
}

repo_boundary_lines() {
  local repo_path="$1" source_dir="$2"
  local lines="- Runtime / source: \`${source_dir}\`"$'\n'
  [[ -f "$repo_path/package.json" ]] && lines="${lines}- Package boundary: \`package.json\`"$'\n'
  [[ -f "$repo_path/pyproject.toml" ]] && lines="${lines}- Python project boundary: \`pyproject.toml\`"$'\n'
  [[ -f "$repo_path/requirements.txt" ]] && lines="${lines}- Dependency boundary: \`requirements.txt\`"$'\n'
  [[ -d "$repo_path/tests" ]] && lines="${lines}- Tests: \`tests/\`"$'\n'
  [[ -d "$repo_path/test" ]] && lines="${lines}- Tests: \`test/\`"$'\n'
  [[ -d "$repo_path/functions" ]] && lines="${lines}- Serverless boundary: \`functions/\`"$'\n'
  [[ -d "$repo_path/infra" ]] && lines="${lines}- Infra boundary: \`infra/\`"$'\n'
  [[ -d "$repo_path/terraform" ]] && lines="${lines}- Infra boundary: \`terraform/\`"$'\n'
  [[ -d "$repo_path/charts" ]] && lines="${lines}- Deployment boundary: \`charts/\`"$'\n'
  [[ -d "$repo_path/android" ]] && lines="${lines}- Android boundary: \`android/\`"$'\n'
  [[ -d "$repo_path/ios" ]] && lines="${lines}- iOS boundary: \`ios/\`"$'\n'
  [[ -d "$repo_path/Assets" ]] && lines="${lines}- Unity assets boundary: \`Assets/\`"$'\n'
  printf '%s' "$lines"
}

repo_context_artifact_lines() {
  local repo_path="$1"
  local lines="" candidate rel
  for candidate in \
    "README.md" "docs/" "architecture.md" "ARCHITECTURE.md" "decisions.md" "DECISIONS.md" \
    "adr/" "ADRs/" "openapi.yaml" "openapi.yml" "swagger.yaml" "swagger.yml" \
    "firebase.json" "schema.prisma" ".github/workflows/" ".github/pull_request_template.md"; do
    if [[ "$candidate" == */ ]]; then
      [[ -e "$repo_path/${candidate%/}" ]] || continue
      rel="${candidate%/}/"
    else
      [[ -e "$repo_path/$candidate" ]] || continue
      rel="$candidate"
    fi
    lines="${lines}- \`${rel}\`"$'\n'
  done
  [[ -n "$lines" ]] || lines="- _No obvious local architecture / contract artifacts detected during bootstrap._"$'\n'
  printf '%s' "$lines"
}

repo_relationship_lines() {
  local current_repo_id="$1" current_repo_path="$2" discovered_rows="$3"
  local current_role current_hint
  current_role="$(detect_repo_role "$current_repo_path" "$current_repo_id")"
  current_hint="$(detect_repo_stack_hint "$current_repo_path" "$current_repo_id" "$current_role")"
  local lines="" repo_id repo_path repo_stack repo_ref repo_abs repo_name repo_role repo_hint
  while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
    [[ -n "$repo_id" && "$repo_id" != "$current_repo_id" ]] || continue
    [[ -n "$repo_abs" ]] || continue
    repo_role="$(detect_repo_role "$repo_abs" "$repo_id")"
    repo_hint="$(detect_repo_stack_hint "$repo_abs" "$repo_id" "$repo_role")"
    if [[ "$current_role" == "frontend" ]]; then
      if [[ "$repo_role" == "backend" ]]; then
        lines="${lines}- Likely consumes APIs or contracts from \`${repo_id}\`"$'\n'
      elif [[ "$repo_role" == "shared" ]]; then
        lines="${lines}- Likely imports shared UI, SDK, or contract code from \`${repo_id}\`"$'\n'
      fi
    elif [[ "$current_role" == "mobile" ]]; then
      if [[ "$repo_role" == "backend" ]]; then
        lines="${lines}- Likely depends on backend or auth contracts from \`${repo_id}\`"$'\n'
      elif [[ "$repo_role" == "shared" ]]; then
        lines="${lines}- Likely shares client models or SDK code with \`${repo_id}\`"$'\n'
      fi
    elif [[ "$current_role" == "backend" ]]; then
      if [[ "$repo_role" == "frontend" || "$repo_role" == "mobile" ]]; then
        lines="${lines}- Likely serves APIs, auth, or shared contracts to \`${repo_id}\`"$'\n'
      elif [[ "$repo_role" == "shared" ]]; then
        lines="${lines}- Likely depends on shared packages or schema contracts from \`${repo_id}\`"$'\n'
      elif [[ "$repo_hint" == "serverless-functions" ]]; then
        lines="${lines}- Likely exchanges events, queues, or auth state with \`${repo_id}\`"$'\n'
      fi
    elif [[ "$current_role" == "shared" ]]; then
      if [[ "$repo_role" == "frontend" || "$repo_role" == "backend" || "$repo_role" == "mobile" ]]; then
        lines="${lines}- Likely exports shared types, SDKs, or contracts to \`${repo_id}\`"$'\n'
      fi
    elif [[ "$current_role" == "infra" ]]; then
      if [[ "$repo_role" != "infra" ]]; then
        lines="${lines}- Likely provisions deployment, runtime, or environment wiring used by \`${repo_id}\`"$'\n'
      fi
    fi
  done <<< "$discovered_rows"
  [[ -n "$lines" ]] || lines="- _No likely cross-repo dependency inferred during bootstrap._"$'\n'
  printf '%s' "$lines"
  return 0
}

