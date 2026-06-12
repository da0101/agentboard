canonical_stream_id() {
  printf 'stream-%s\n' "$1"
}

canonical_domain_id() {
  printf 'dom-%s\n' "$1"
}

stream_files() {
  local file base
  for file in ./.platform/work/*.md; do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    case "$base" in
      ACTIVE.md|BRIEF.md|TEMPLATE.md)
        continue
        ;;
    esac
    printf '%s\n' "$file"
  done
}

domain_files() {
  local file base
  for file in ./.platform/domains/*.md; do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    [[ "$base" == "TEMPLATE.md" ]] && continue
    printf '%s\n' "$file"
  done
}

git_file_has_worktree_changes() {
  local file="$1"
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  [[ -n "$(git status --porcelain -- "$file" 2>/dev/null)" ]]
}

stream_file_by_id() {
  local wanted_id="$1" file
  while IFS= read -r file; do
    [[ "$(frontmatter_value "$file" "stream_id")" == "$wanted_id" ]] || continue
    printf '%s\n' "$file"
    return 0
  done < <(stream_files)
  return 1
}

domain_file_by_id() {
  local wanted_id="$1" file
  while IFS= read -r file; do
    [[ "$(frontmatter_value "$file" "domain_id")" == "$wanted_id" ]] || continue
    printf '%s\n' "$file"
    return 0
  done < <(domain_files)
  return 1
}

repo_manifest_file() {
  local repo_path="$1"
  local candidate
  for candidate in \
    "package.json" "pyproject.toml" "requirements.txt" "Cargo.toml" "go.mod" \
    "pom.xml" "build.gradle" "build.gradle.kts" "Podfile" "CMakeLists.txt" \
    "Makefile" "pubspec.yaml" "composer.json" "Gemfile" "angular.json"; do
    [[ -f "$repo_path/$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done

  local entry
  for entry in "$repo_path"/*.xcodeproj "$repo_path"/*.csproj "$repo_path"/*.sln; do
    [[ -e "$entry" ]] || continue
    printf '%s\n' "$(basename "$entry")"
    return 0
  done

  return 1
}

repo_primary_source_dir() {
  local repo_path="$1" candidate
  for candidate in src app lib cmd server backend frontend packages; do
    [[ -d "$repo_path/$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  printf '%s\n' "."
}

guess_repo_stack() {
  local repo_path="$1" repo_id="${2:-}"
  local role hint
  role="$(detect_repo_role "$repo_path" "$repo_id")"
  hint="$(detect_repo_stack_hint "$repo_path" "$repo_id" "$role")"
  format_repo_stack "$role" "$hint"
}

discover_child_repos() {
  local root="$1"
  local manifest_regex='^(package\.json|pyproject\.toml|requirements\.txt|Cargo\.toml|go\.mod|pom\.xml|build\.gradle|build\.gradle\.kts|Podfile|CMakeLists\.txt|Makefile|pubspec\.yaml|composer\.json|Gemfile|.*\.xcodeproj|.*\.csproj|.*\.sln|angular\.json)$'
  local entry name inner base is_repo repo_id stack ref_file abs_path

  shopt -s nullglob dotglob
  for entry in "$root"/*; do
    [[ -d "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ "$name" =~ ^(\.git|\.platform|\.claude|\.agents|\.codex|\.idea|\.vscode|node_modules)$ ]] && continue

    is_repo=0
    if [[ -d "$entry/.git" ]]; then
      is_repo=1
    else
      for inner in "$entry"/*; do
        base="$(basename "$inner")"
        if [[ -f "$inner" ]] && [[ "$base" =~ $manifest_regex ]]; then
          is_repo=1
          break
        fi
      done
    fi

    (( is_repo )) || continue
    repo_id="$(slugify "$name")"
    abs_path="$(cd "$entry" && pwd)"
    stack="$(guess_repo_stack "$entry" "$repo_id")"
    ref_file="${repo_id}.md"
    printf '%s|%s|%s|%s|%s|%s\n' "$repo_id" "./$name" "$stack" "$ref_file" "$abs_path" "$name"
  done
  shopt -u nullglob dotglob
}

concrete_repo_rows() {
  local repos_file="$1"
  local repo_name repo_path repo_stack repo_ref abs_path display_name
  while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
    [[ -n "$repo_name" ]] || continue
    if [[ "$repo_name" =~ ^_repo- || "$repo_path" =~ \.\./repo- || "$repo_name" =~ ^_example- ]]; then
      continue
    fi
    abs_path="$(resolve_repo_path "$repos_file" "$repo_path" 2>/dev/null)" || abs_path=""
    display_name="$(basename "${abs_path:-$repo_path}")"
    printf '%s|%s|%s|%s|%s|%s\n' "$repo_name" "$repo_path" "$repo_stack" "$repo_ref" "$abs_path" "$display_name"
  done < <(repo_rows_from_registry "$repos_file")
}

stream_next_action() {
  local stream_file="$1" out
  out="$(awk '
    /^## Resume state/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^[[:space:]]*-[[:space:]]+\*\*Next action:\*\*[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]+\*\*Next action:\*\*[[:space:]]*/, "", $0)
      if ($0 ~ /^_.*_$/) exit
      if ($0 == "—" || $0 == "") exit
      print
      exit
    }
  ' "$stream_file")"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  awk '
    /^## Next action/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^_.*_$/) next
      print
      exit
    }
  ' "$stream_file"
}

session_stream_map_file() {
  printf '%s\n' "./.platform/.session-streams.tsv"
}

brief_primary_stream_slug() {
  local brief="./.platform/work/BRIEF.md"
  [[ -f "$brief" ]] || return 1

  local slug
  slug="$(sed -n 's/^\*\*Stream file:\*\* `work\/\([^`]*\)\.md`$/\1/p' "$brief")"
  slug="${slug%%$'\n'*}"
  [[ -n "$slug" && -f "./.platform/work/${slug}.md" ]] || return 1
  printf '%s\n' "$slug"
}

active_stream_slugs() {
  local active="./.platform/work/ACTIVE.md"
  [[ -f "$active" ]] || return 0
  stream_rows_from_active "$active" | awk -F'|' '
    {
      slug = $1
      status = $3
      if (status == "" || status == "done" || status == "archived" || status == "closed") next
      print slug
    }
  '
}

session_stream_lookup() {
  local session_id="$1" map_file
  [[ -n "$session_id" ]] || return 1
  map_file="$(session_stream_map_file)"
  [[ -f "$map_file" ]] || return 1

  awk -F'\t' -v session_id="$session_id" '
    $1 == session_id { print $2; found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$map_file"
}

remember_session_stream() {
  local session_id="$1" stream_slug="$2" map_file tmp
  [[ -n "$session_id" && -n "$stream_slug" ]] || return 1

  map_file="$(session_stream_map_file)"
  mkdir -p "$(dirname "$map_file")"
  tmp="$(mktemp)"
  if [[ -f "$map_file" ]]; then
    awk -F'\t' -v session_id="$session_id" '$1 != session_id { print }' "$map_file" > "$tmp"
  fi
  printf '%s\t%s\n' "$session_id" "$stream_slug" >> "$tmp"
  mv "$tmp" "$map_file"
}

stream_exists() {
  local stream_slug="$1"
  [[ -n "$stream_slug" && -f "./.platform/work/${stream_slug}.md" ]]
}

resolve_current_stream() {
  local explicit_stream="${1:-}" session_id="${2:-}"
  local stream_slug active_slugs active_count

  if [[ -n "$explicit_stream" ]]; then
    stream_exists "$explicit_stream" || return 1
    printf '%s\n' "$explicit_stream"
    return 0
  fi

  if [[ -n "${AGENTBOARD_STREAM:-}" ]]; then
    if stream_exists "$AGENTBOARD_STREAM"; then
      printf '%s\n' "$AGENTBOARD_STREAM"
      return 0
    fi
  fi

  if [[ -n "$session_id" ]]; then
    stream_slug="$(session_stream_lookup "$session_id" 2>/dev/null || true)"
    if [[ -n "$stream_slug" ]] && stream_exists "$stream_slug"; then
      printf '%s\n' "$stream_slug"
      return 0
    fi
  fi

  stream_slug="$(brief_primary_stream_slug 2>/dev/null || true)"
  if [[ -n "$stream_slug" ]]; then
    printf '%s\n' "$stream_slug"
    return 0
  fi

  active_slugs="$(active_stream_slugs)"
  active_count="$(printf '%s\n' "$active_slugs" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$active_count" -eq 1 ]]; then
    printf '%s\n' "$active_slugs"
    return 0
  fi

  return 1
}

stream_resume_field() {
  local stream_file="$1" label="$2"
  awk -v label="$label" '
    BEGIN { pat = "^[[:space:]]*-[[:space:]]+\\*\\*" label ":\\*\\*[[:space:]]*" }
    /^## Resume state/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && $0 ~ pat {
      sub(pat, "", $0)
      print
      exit
    }
  ' "$stream_file"
}

legacy_brief_stream_slugs() {
  local brief="$1"
  awk '
    /^## Active streams$/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      if (match($0, /^[0-9]+\. `([^`]*)`/, m)) print m[1]
    }
  ' "$brief"
  return 0
}
