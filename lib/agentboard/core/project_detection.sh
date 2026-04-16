write_brief_stub() {
  local brief="$1" project_name="$2" stream_slug="$3" domain_slugs="$4" status="$5"
  local relevant_context=""
  local domain_slug
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    relevant_context="${relevant_context}- \`.platform/domains/${domain_slug}.md\` — relevant domain for this stream"$'\n'
  done <<< "$domain_slugs"
  [[ -n "$relevant_context" ]] || relevant_context="- \`.platform/domains/<name>.md\` — primary domain for this stream"$'\n'

  cat > "$brief" <<EOF
# Feature Brief — $project_name

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** $stream_slug
**Status:** $status
**Stream file:** \`work/$stream_slug.md\`

---

## What we're building

_TODO: describe the feature in 2–3 sentences._

## Why

_TODO: state the user or business reason._

## What done looks like

- _TODO_
- _TODO_
- _TODO_

## Architecture decisions locked

- _TODO_
- _TODO_

## Current state

_TODO: summarize what exists and what is left._

See \`work/ACTIVE.md\` for stream status.

## Relevant context

> Only load the files listed here. Everything else is out of scope for this feature.
> Prefer \`.platform/domains/<name>.md\` files (cross-layer, focused) over repo-wide files.
> Repo files (\`backend.md\`, \`admin.md\`, etc.) are conventions — load only if you need to understand patterns.

${relevant_context}

**Do not load:** _TODO_
**Never load:** \`work/archive/*\`

## Key files

- _TODO_
- _TODO_
- _TODO_
EOF
}

# -----------------------------------------------------------------------------
# Empty-folder / hub detection
# -----------------------------------------------------------------------------

# detect_folder_kind <target>
# Prints one of: "project" | "empty" | "hub-candidate"
#
#   project         — folder contains code files, manifest files, or source
#                     subdirectories belonging to this folder itself (not
#                     siblings).
#   empty           — folder is empty for agentboard purposes (only README,
#                     LICENSE, .git/, .gitignore, .DS_Store, .claude/,
#                     .platform/ and similar).
#   hub-candidate   — folder contains ONLY subdirectories, each of which looks
#                     like its own repo (has .git/ or its own manifest).
detect_folder_kind() {
  local target="$1"

  # Files that are OK in an "empty" folder and do not disqualify it.
  local ignore_files_regex='^(\.DS_Store|\.gitignore|\.gitkeep|LICENSE|LICENSE\..*|README\.md|README\.txt|README\.rst|README)$'
  local ignore_dirs_regex='^(\.git|\.claude|\.platform|\.vscode|\.idea|\.github)$'

  # Extensions that count as "code files".
  local code_ext_regex='\.(py|js|mjs|cjs|ts|tsx|jsx|go|rs|java|kt|kts|swift|dart|rb|php|cs|cpp|cc|cxx|c|h|hpp|m|mm|scala|clj|cljs|ex|exs|lua|pl|sh|zsh|bash)$'

  # Manifest files that make a folder a project.
  local manifest_regex='^(package\.json|pyproject\.toml|requirements\.txt|Cargo\.toml|go\.mod|pom\.xml|build\.gradle|build\.gradle\.kts|Podfile|CMakeLists\.txt|Makefile|pubspec\.yaml|composer\.json|Gemfile|.*\.xcodeproj|.*\.csproj|.*\.sln)$'

  # Source subdirectories that make a folder a project (NOT a hub).
  local source_dir_regex='^(src|lib|app|backend|frontend|server|client|widget|pkg|cmd|internal|tests|test|spec|public|views|controllers|models|components|pages|api)$'

  local has_code=0
  local has_manifest=0
  local has_source_dir=0
  local sibling_repo_count=0
  local plain_subdir_count=0
  local entry name base

  shopt -s nullglob dotglob

  for entry in "$target"/*; do
    name="$(basename "$entry")"

    if [[ -d "$entry" ]]; then
      # Ignore noise dirs up front
      if [[ "$name" =~ $ignore_dirs_regex ]]; then
        continue
      fi

      # Is this subdirectory its own repo? (.git/ OR its own manifest)
      local is_sibling_repo=0
      if [[ -d "$entry/.git" ]]; then
        is_sibling_repo=1
      else
        # Check for manifest inside the subdir
        local inner
        for inner in "$entry"/*; do
          base="$(basename "$inner")"
          if [[ -f "$inner" ]] && [[ "$base" =~ $manifest_regex ]]; then
            is_sibling_repo=1
            break
          fi
        done
      fi

      if (( is_sibling_repo )); then
        sibling_repo_count=$((sibling_repo_count + 1))
        plain_subdir_count=$((plain_subdir_count + 1))
        continue
      fi

      # Not a sibling repo — is it a source dir of THIS folder?
      if [[ "$name" =~ $source_dir_regex ]]; then
        has_source_dir=1
      fi

      plain_subdir_count=$((plain_subdir_count + 1))

    elif [[ -f "$entry" ]]; then
      if [[ "$name" =~ $ignore_files_regex ]]; then
        continue
      fi
      if [[ "$name" =~ $manifest_regex ]]; then
        has_manifest=1
        continue
      fi
      if [[ "$name" =~ $code_ext_regex ]]; then
        has_code=1
        continue
      fi
    fi
  done

  shopt -u nullglob dotglob

  # If we found code or a manifest or a real source subdir belonging to this
  # folder, it's a project.
  if (( has_code )) || (( has_manifest )) || (( has_source_dir )); then
    echo "project"
    return
  fi

  # If every non-ignored subdir is itself a repo AND there are at least 1 of
  # them, treat it as a strong hub candidate.
  if (( sibling_repo_count >= 1 )) && (( sibling_repo_count == plain_subdir_count )); then
    echo "hub-candidate"
    return
  fi

  echo "empty"
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

# skill_description <path-to-SKILL.md>
# Extracts the 'description' field from a skill's YAML frontmatter, trims it
# to a short first-sentence summary suitable for one-line display.
skill_description() {
  local file="$1"
  [[ -f "$file" ]] || { echo ""; return; }
  local desc
  desc="$(awk '/^description:/ {
    sub(/^description: *"?/, "");
    sub(/"$/, "");
    print; exit
  }' "$file" 2>/dev/null)"
  # First sentence only
  desc="${desc%%. *}"
  # Trim trailing period
  desc="${desc%.}"
  # Truncate if still too long
  if (( ${#desc} > 64 )); then
    desc="${desc:0:61}..."
  fi
  echo "$desc"
}

