# -----------------------------------------------------------------------------
# Frontmatter and markdown-state parsers.
#
# Readers for the YAML-ish frontmatter on stream/domain files, their legacy
# (pre-frontmatter) markdown equivalents, and the table-based state files
# (work/ACTIVE.md, repos.md). Includes the slug-similarity / repo-id inference
# helpers built on top of those parsers. Pure bash + awk/sed/grep — no deps.
# -----------------------------------------------------------------------------

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (!seen) { seen = 1; in_fm = 1; next }
      if (in_fm) exit
    }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      sub("^[^:]+:[[:space:]]*", "", $0)
      print
      exit
    }
  ' "$file"
}

has_frontmatter() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local first_line
  IFS= read -r first_line < "$file" || true
  [[ "$first_line" == "---" ]]
}

legacy_stream_value() {
  local file="$1" label="$2"
  sed -n "s/^\\*\\*${label}:\\*\\* //p; /^\\*\\*${label}:\\*\\* /q" "$file"
}

is_legacy_stream_file() {
  local file="$1"
  has_frontmatter "$file" && return 1
  grep -q '^# ' "$file" 2>/dev/null || return 1
  grep -q '^\*\*Type:\*\* ' "$file" 2>/dev/null || return 1
  grep -q '^\*\*Status:\*\* ' "$file" 2>/dev/null || return 1
  return 0
}

is_legacy_domain_file() {
  local file="$1"
  has_frontmatter "$file" && return 1
  grep -Eq '^# (Domain: |[[:alnum:]])' "$file" 2>/dev/null || return 1
  grep -Eq '^## Backend|^## Frontend|^## Mobile|^## API endpoints|^## Key files' "$file" 2>/dev/null || return 1
  return 0
}

is_legacy_brief_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  grep -q '^## Active streams' "$file" 2>/dev/null
}

legacy_closure_approved() {
  local file="$1" value
  value="$(sed -n 's/^\*\*closure_approved:\*\* \([^ ]*\).*$/\1/p; /^\*\*closure_approved:\*\* /q' "$file")"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "true" ]] && printf 'true\n' || printf 'false\n'
}

score_slug_similarity() {
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then
    printf '100\n'
    return 0
  fi
  awk -v a="$a" -v b="$b" '
    function stopword(tok) {
      return tok == "admin" || tok == "api" || tok == "flow" || tok == "analysis" || \
             tok == "error" || tok == "errors" || tok == "bug" || tok == "bugs" || \
             tok == "stability" || tok == "fix" || tok == "report" || tok == "reports"
    }
    function norm(tok) {
      tok=tolower(tok)
      if (length(tok) > 3 && tok ~ /s$/) sub(/s$/, "", tok)
      if (stopword(tok)) return ""
      return tok
    }
    BEGIN {
      n = split(a, A, /-/)
      for (i = 1; i <= n; i++) {
        tok = norm(A[i])
        if (tok != "") seen[tok] = 1
      }
      m = split(b, B, /-/)
      score = 0
      for (i = 1; i <= m; i++) {
        tok = norm(B[i])
        if (tok in seen) score++
      }
      print score
    }
  '
}

infer_stream_domain_slugs() {
  local stream_slug="$1"
  local best_score=0 score domain_file domain_slug matches=""
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    domain_slug="$(basename "$domain_file" .md)"
    score="$(score_slug_similarity "$stream_slug" "$domain_slug")"
    if (( score > best_score )); then
      best_score="$score"
      matches="$domain_slug"
    elif (( score > 0 && score == best_score )); then
      matches="${matches}"$'\n'"$domain_slug"
    fi
  done < <(domain_files)
  if (( best_score > 0 )); then
    printf '%s\n' "$matches" | unique_nonempty_lines
  fi
  return 0
}

infer_repo_ids_from_text() {
  local file="$1" repos_file="$2"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"
  if [[ -z "$repo_rows" ]]; then
    printf 'repo-primary\n'
    return 0
  fi

  local repo_name repo_path repo_stack repo_ref matched alias path_base ref_base
  while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
    [[ -n "$repo_name" ]] || continue
    matched=0
    path_base="$(basename "${repo_path#./}")"
    ref_base="${repo_ref%.md}"
    for alias in "$repo_name" "$path_base" "$ref_base"; do
      [[ -z "$alias" || "$alias" == "." ]] && continue
      if grep -qiF "$alias" "$file"; then
        matched=1
        break
      fi
    done
    if (( !matched )); then
      case "$repo_name" in
        *backend*|*greybox*)
          grep -Eq '^## Backend|^### Backend|^## Backend / source of truth|Backend \(' "$file" && matched=1
          ;;
        *frontend*)
          grep -Eq '^## Frontend|^### Frontend|Frontend \(' "$file" && matched=1
          ;;
        *mobile*|*ios*|*android*)
          grep -Eq '^## Mobile|^### Mobile|Mobile \(' "$file" && matched=1
          ;;
      esac
    fi
    (( matched )) && printf '%s\n' "$repo_name"
  done <<< "$repo_rows"
  return 0
}

infer_domain_repo_ids() {
  local domain_file="$1" repos_file="$2"
  infer_repo_ids_from_text "$domain_file" "$repos_file" | unique_nonempty_lines
  return 0
}

infer_stream_repo_ids() {
  local stream_file="$1" repos_file="$2" domain_slugs="$3"
  local repo_id domain_slug domain_file
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || continue
    if has_frontmatter "$domain_file"; then
      inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")"
    else
      infer_domain_repo_ids "$domain_file" "$repos_file"
    fi
  done <<< "$domain_slugs"
  infer_repo_ids_from_text "$stream_file" "$repos_file"
  return 0
}

inline_array_items() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" || "$value" == "[]" ]] && return 0
  value="${value#\[}"
  value="${value%\]}"

  local item
  local -a items=()
  IFS=',' read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && printf '%s\n' "$item"
  done
}

frontmatter_inline_array() {
  local item out=""
  while IFS= read -r item; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    if [[ -z "$out" ]]; then
      out="$item"
    else
      out="$out, $item"
    fi
  done
  printf '[%s]\n' "$out"
}

brief_is_placeholder() {
  local brief="$1"
  [[ ! -f "$brief" ]] && return 0
  grep -q "_not yet set — fill this in when you start your first workstream_" "$brief"
}

stream_rows_from_active() {
  local active="$1"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^## / { exit }
    {
      slug = trim($2)
      type = trim($3)
      status = trim($4)
      agent = trim($5)
      updated = trim($6)
      if (slug == "" || slug == "Stream" || slug == "_(none)_" || slug ~ /^-+$/) next
      if (status == "closed") next
      printf "%s|%s|%s|%s|%s\n", slug, type, status, agent, updated
    }
  ' "$active"
}

repo_rows_from_registry() {
  local repos_file="$1"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
    /^## Repos/ { in_repos = 1; next }
    in_repos && /^## / { exit }
    {
      if (!in_repos) next
      repo = trim($2)
      path = trim($3)
      stack = trim($4)
      ref = trim($5)
      if (repo == "" || repo == "Slug" || repo == "Repo" || repo == "Repo ID" || repo ~ /^-+$/) next
      printf "%s|%s|%s|%s\n", repo, path, stack, ref
    }
  ' "$repos_file"
}

repo_row_for_id() {
  local repo_rows="$1" repo_id="$2"
  printf '%s\n' "$repo_rows" | awk -F'|' -v repo_id="$repo_id" '$1 == repo_id { print; exit }'
}

resolve_repo_path() {
  local repos_file="$1" repo_path="$2"
  if [[ "$repo_path" = /* ]]; then
    printf '%s\n' "$repo_path"
  else
    (
      cd "$(dirname "$repos_file")/.." 2>/dev/null || exit 1
      cd "$repo_path" 2>/dev/null || exit 1
      pwd
    )
  fi
}
