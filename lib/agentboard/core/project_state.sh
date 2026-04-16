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

replace_repos_table() {
  local repos_file="$1" rows="$2"
  local tmp tmp_rows
  tmp="$(mktemp)"
  tmp_rows="$(mktemp)"
  printf '%s' "$rows" > "$tmp_rows"
  awk -v rows_file="$tmp_rows" '
    /^## Repos$/ { print; in_repos=1; next }
    in_repos && inserted && NF == 0 { in_repos=0; print ""; next }
    in_repos && /^\|/ {
      if (!inserted) {
        while ((getline line < rows_file) > 0) print line
        close(rows_file)
        inserted=1
      }
      next
    }
    { print }
  ' "$repos_file" > "$tmp"
  mv "$tmp" "$repos_file"
  rm -f "$tmp_rows"
}

write_sync_repos_array() {
  local sync_script="$1" extra_paths="$2"
  local tmp tmp_paths
  tmp="$(mktemp)"
  tmp_paths="$(mktemp)"
  printf '%s' "$extra_paths" > "$tmp_paths"
  awk -v paths_file="$tmp_paths" '
    /^REPOS=\($/ {
      print "REPOS=("
      print "  # Auto-detected: the repo containing this script."
      print "  \"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")/../..\" && pwd)\""
      while ((getline line < paths_file) > 0) if (line != "") print "  \"" line "\""
      close(paths_file)
      print ")"
      in_repos=1
      next
    }
    in_repos && /^\)$/ { in_repos=0; next }
    in_repos { next }
    { print }
  ' "$sync_script" > "$tmp"
  mv "$tmp" "$sync_script"
  rm -f "$tmp_paths"
}

write_bootstrap_reference() {
  local target="$1" repo_name="$2" repo_display_name="$3" repo_abs_path="$4" role="$5" hint="$6" manifest="$7" source_dir="$8" commands="$9" relationships="${10}" entrypoints="${11}" boundaries="${12}" artifacts="${13}"
  local dev_cmd test_cmd build_cmd
  IFS='|' read -r dev_cmd test_cmd build_cmd <<< "$commands"
  cat > "$target" <<EOF
# $repo_display_name — Deep Reference

> Bootstrap-generated on $(today). Replace placeholders during activation or first real work in this repo.
> Repo: \`$repo_abs_path\`

## What this repo is

_Bootstrap placeholder: summarize the repo purpose, users, and scope._

## Inferred identity

- Repo role: $role
- Stack hint: ${hint:-unknown}
- Manifest: ${manifest:-unknown}
- Primary source dir: $source_dir

## Likely entrypoints

${entrypoints}

## Likely boundaries

${boundaries}

## Local context artifacts

${artifacts}

## Inferred commands

- Dev: \`${dev_cmd}\`
- Test: \`${test_cmd}\`
- Build: \`${build_cmd}\`

## Cross-repo dependencies

${relationships}

## Open questions

- _What is the true entrypoint and runtime boundary for this repo?_
- _What conventions or gotchas should every agent load before changing this repo?_
EOF
}

stream_next_action() {
  local stream_file="$1"
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

markdown_section_excerpt() {
  local file="$1" header="$2"
  awk -v header="$header" '
    $0 == header { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^>/) next
      if ($0 ~ /^_.*_$/) next
      if ($0 ~ /TODO/) next
      if ($0 == "See `work/ACTIVE.md` for stream status.") next
      print
      count++
      if (count >= 2) exit
    }
  ' "$file"
}

markdown_section_prose() {
  local file="$1" header="$2" max_lines="${3:-2}"
  awk -v header="$header" -v max_lines="$max_lines" '
    $0 == header { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^>/) next
      if ($0 ~ /^_.*_$/) next
      if ($0 ~ /^\*\*.*\*\*$/) next
      if ($0 ~ /^[-*] /) next
      if ($0 ~ /^[0-9]+\. /) next
      if ($0 ~ /^```/) next
      print
      count++
      if (count >= max_lines) exit
    }
  ' "$file"
  return 0
}

markdown_section_list_items() {
  local file="$1" header="$2" max_items="${3:-3}"
  awk -v header="$header" -v max_items="$max_items" '
    $0 == header { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      line = $0
      if (line ~ /^- \[[ xX]\] /) sub(/^- \[[ xX]\] /, "", line)
      else if (line ~ /^- /) sub(/^- /, "", line)
      else next
      if (line == "") next
      print line
      count++
      if (count >= max_items) exit
    }
  ' "$file"
  return 0
}

stream_key_decision_items() {
  local stream_file="$1" max_items="${2:-2}"
  awk -v max_items="$max_items" '
    /^## Key decisions/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      line = $0
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^_.*_$/) next
      sub(/^[0-9]{4}-[0-9]{2}-[0-9]{2} — /, "", line)
      sub(/^[-*] /, "", line)
      if (line == "") next
      print line
      count++
      if (count >= max_items) exit
    }
  ' "$stream_file"
  return 0
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

repo_ref_lines_for_ids() {
  local repos_file="$1" repo_ids="$2"
  local repo_rows="" repo_id repo_row repo_name repo_path repo_stack repo_ref
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
    [[ -n "$repo_row" ]] || continue
    IFS='|' read -r repo_name repo_path repo_stack repo_ref <<< "$repo_row"
    [[ -n "$repo_ref" ]] || continue
    printf '%s\n' "- \`.platform/${repo_ref}\` — repo-wide reference for \`${repo_id}\`; load only if stream work needs repo-specific conventions"
  done <<< "$repo_ids"
  return 0
}

render_brief_from_stream() {
  local project_name="$1" stream_slug="$2" stream_status="$3" stream_file="$4" repos_file="$5"

  local domain_slugs repo_ids what_building why done_items decision_items next_action current_state
  domain_slugs="$(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")"
  repo_ids="$(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")"

  what_building="$(markdown_section_prose "$stream_file" "## Scope" 2)"
  [[ -n "$what_building" ]] || what_building="$(markdown_section_prose "$stream_file" "## Overview" 2)"
  [[ -n "$what_building" ]] || what_building="Continue the \`$stream_slug\` stream described in \`work/$stream_slug.md\`."

  why="$(markdown_section_prose "$stream_file" "## Why" 1)"
  [[ -n "$why" ]] || why="Reduce handoff overhead and keep this stream resumable across Claude, Codex, and Gemini."

  done_items="$(markdown_section_list_items "$stream_file" "## Done criteria" 3)"
  [[ -n "$done_items" ]] || done_items="See \`.platform/work/${stream_slug}.md\` for the concrete acceptance criteria."

  decision_items="$(stream_key_decision_items "$stream_file" 2)"
  [[ -n "$decision_items" ]] || decision_items="See \`.platform/work/${stream_slug}.md\` for decision history before changing scope."

  next_action="$(stream_next_action "$stream_file")"
  [[ -n "$next_action" ]] || next_action="Check \`.platform/work/${stream_slug}.md\` and update the next-action section."
  current_state="Status is ${stream_status:-unknown}. Next action: ${next_action}"

  local relevant_context="" domain_slug repo_ref_lines="" key_files=""
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    relevant_context="${relevant_context}- \`.platform/domains/${domain_slug}.md\` — relevant domain for this stream"$'\n'
  done <<< "$domain_slugs"
  repo_ref_lines="$(repo_ref_lines_for_ids "$repos_file" "$repo_ids")"
  [[ -n "$repo_ref_lines" ]] && relevant_context="${relevant_context}${repo_ref_lines}"$'\n'
  [[ -n "$relevant_context" ]] || relevant_context="- \`.platform/domains/<name>.md\` — primary domain for this stream"$'\n'

  key_files="- \`.platform/work/${stream_slug}.md\` — stream scope, done criteria, decisions, next action"$'\n'
  key_files="${key_files}- \`.platform/work/ACTIVE.md\` — current status board"$'\n'
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    key_files="${key_files}- \`.platform/domains/${domain_slug}.md\` — cross-layer domain reference"$'\n'
  done <<< "$domain_slugs"

  cat <<EOF
# Feature Brief — $project_name

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** $stream_slug
**Status:** $stream_status
**Stream file:** \`work/$stream_slug.md\`

---

## What we're building

$what_building

## Why

$why

## What done looks like

$(while IFS= read -r item; do [[ -n "$item" ]] && printf -- '- %s\n' "$item"; done <<< "$done_items")

## Architecture decisions locked

$(while IFS= read -r item; do [[ -n "$item" ]] && printf -- '- %s\n' "$item"; done <<< "$decision_items")

## Current state

$current_state

See \`work/ACTIVE.md\` for stream status.

## Relevant context

> Only load the files listed here. Everything else is out of scope for this feature.
> Prefer \`.platform/domains/<name>.md\` files (cross-layer, focused) over repo-wide files.
> Repo files (\`backend.md\`, \`admin.md\`, etc.) are conventions — load only if you need to understand patterns.

$relevant_context
**Do not load:** unrelated streams and domain files outside this feature
**Never load:** \`work/archive/*\`

## Key files

$key_files
EOF
  return 0
}

