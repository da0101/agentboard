# Stream/registry repair helpers for ab repair.

_repair_active_rows() {
  [[ -f ./.platform/work/ACTIVE.md ]] && stream_rows_from_active ./.platform/work/ACTIVE.md
}

_repair_active_row_for_slug() {
  local slug="$1"
  _repair_active_rows | awk -F'|' -v slug="$slug" '$1 == slug { print; exit }'
}

_repair_array_or_default() {
  local value="$1" fallback="$2"
  if [[ -n "$(inline_array_items "$value")" ]]; then
    inline_array_items "$value"
  else
    printf '%s\n' "$fallback" | unique_nonempty_lines
  fi
}

_repair_first_domain_slug() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    basename "$f" .md
    return 0
  done < <(domain_files)
}

_repair_stream_needs_metadata() {
  local file="$1" slug="$2" row="$3" value
  has_frontmatter "$file" || return 1
  value="$(frontmatter_value "$file" stream_id)"
  [[ "$value" != "$(canonical_stream_id "$slug")" ]] && return 0
  value="$(frontmatter_value "$file" slug)"
  [[ "$value" != "$slug" ]] && return 0
  for key in type status agent_owner created_at updated_at closure_approved; do
    value="$(frontmatter_value "$file" "$key")"
    is_placeholder_value "$value" && return 0
  done
  value="$(frontmatter_value "$file" closure_approved)"
  [[ "$value" != "true" && "$value" != "false" ]] && return 0
  [[ -z "$(inline_array_items "$(frontmatter_value "$file" domain_slugs)")" ]] && return 0
  [[ -z "$(inline_array_items "$(frontmatter_value "$file" repo_ids)")" ]] && return 0
  if [[ -n "$row" ]]; then
    local row_status
    IFS='|' read -r _ _ row_status _ _ <<< "$row"
    value="$(frontmatter_value "$file" status)"
    [[ -n "$row_status" && "$value" != "$row_status" ]] && return 0
  fi
  return 1
}

_repair_write_stream_metadata() {
  local file="$1" slug="$2" row="$3" repos_file="./.platform/repos.md"
  local row_type="" row_status="" row_agent="" row_updated=""
  [[ -n "$row" ]] && IFS='|' read -r _ row_type row_status row_agent row_updated <<< "$row"

  local stream_type status agent created updated closure domains repos inferred_domains fallback_domain body tmp
  stream_type="$(frontmatter_value "$file" type)"
  status="$(frontmatter_value "$file" status)"
  agent="$(frontmatter_value "$file" agent_owner)"
  created="$(frontmatter_value "$file" created_at)"
  updated="$(frontmatter_value "$file" updated_at)"
  closure="$(frontmatter_value "$file" closure_approved)"

  [[ -z "$stream_type" || "$stream_type" == *"<"* ]] && stream_type="${row_type:-feature}"
  [[ -z "$status" || "$status" == *"<"* ]] && status="${row_status:-planning}"
  [[ -n "$row_status" ]] && status="$row_status"
  [[ -z "$agent" || "$agent" == *"<"* ]] && agent="${row_agent:-codex}"
  [[ -z "$created" || "$created" == *"<"* ]] && created="${row_updated:-$(today)}"
  [[ -z "$updated" || "$updated" == *"<"* ]] && updated="${row_updated:-$created}"
  [[ "$closure" != "true" && "$closure" != "false" ]] && closure="false"

  fallback_domain="$(_repair_first_domain_slug)"
  inferred_domains="$(infer_stream_domain_slugs "$slug")"
  [[ -z "$inferred_domains" ]] && inferred_domains="$fallback_domain"
  domains="$(_repair_array_or_default "$(frontmatter_value "$file" domain_slugs)" "$inferred_domains")"
  repos="$(_repair_array_or_default "$(frontmatter_value "$file" repo_ids)" "$(infer_stream_repo_ids "$file" "$repos_file" "$domains")")"
  [[ -z "$repos" ]] && repos="repo-primary"

  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
---
stream_id: $(canonical_stream_id "$slug")
slug: $slug
type: $stream_type
status: $status
agent_owner: $agent
domain_slugs: $(frontmatter_inline_array <<< "$domains")
repo_ids: $(frontmatter_inline_array <<< "$repos")
created_at: $created
updated_at: $updated
closure_approved: $closure
---

EOF
  if has_frontmatter "$file"; then
    awk 'BEGIN{fm=0; seen=0} /^---[[:space:]]*$/{ if(!seen){seen=1; fm=1; next} if(fm){fm=0; next} } !fm{print}' "$file" >> "$tmp"
  else
    cat "$file" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

_repair_prune_missing_active_rows() {
  local active="./.platform/work/ACTIVE.md" tmp
  [[ -f "$active" ]] || return 1
  tmp="$(mktemp)"
  awk -F'|' '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\|/ {
      slug=trim($2)
      if (slug != "" && slug != "Stream" && slug !~ /^-+$/ && slug != "_(none)_") {
        if (slug ~ /^[A-Za-z0-9._-]+$/ && system("[ -f ./.platform/work/" slug ".md ]") != 0) next
      }
    }
    { print }
  ' "$active" > "$tmp"
  if cmp -s "$active" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$active"
  return 0
}

_repair_single_active_slug() {
  _repair_active_rows | awk -F'|' 'NF && system("[ -f ./.platform/work/" $1 ".md ]") == 0 { count++; slug=$1; status=$3 } END { if (count == 1) print slug "|" status }'
}

_repair_brief_if_single_active() {
  local brief="./.platform/work/BRIEF.md" single slug status stream_file
  [[ -f "$brief" ]] || return 1
  single="$(_repair_single_active_slug)"
  [[ -n "$single" ]] || return 1
  slug="${single%%|*}"
  status="${single##*|}"
  stream_file="./.platform/work/${slug}.md"
  if grep -q "\\*\\*Stream file:\\*\\* \`work/${slug}.md\`" "$brief" 2>/dev/null; then
    return 1
  fi
  render_brief_from_stream "$(basename "$(pwd)")" "$slug" "$status" "$stream_file" "./.platform/repos.md" > "$brief"
  return 0
}

_repair_stream_registry() {
  local dry_run="$1" changed=0 file slug row
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    slug="$(basename "$file" .md)"
    row="$(_repair_active_row_for_slug "$slug")"
    if _repair_stream_needs_metadata "$file" "$slug" "$row"; then
      if (( dry_run )); then
        warn "$file has incomplete or non-canonical stream metadata"
      else
        _repair_write_stream_metadata "$file" "$slug" "$row"
        ok "$file: repaired stream metadata" >&2
      fi
      changed=$((changed + 1))
    fi
  done < <(stream_files)

  if [[ -f ./.platform/work/ACTIVE.md ]]; then
    if (( dry_run )); then
      while IFS='|' read -r slug _ _ _ _; do
        [[ -n "$slug" && ! -f "./.platform/work/${slug}.md" ]] && { warn "ACTIVE.md references missing stream '$slug'"; changed=$((changed + 1)); }
      done < <(_repair_active_rows)
    elif _repair_prune_missing_active_rows; then
      ok "work/ACTIVE.md: removed rows for missing stream files" >&2
      changed=$((changed + 1))
    fi
  fi

  if (( ! dry_run )) && _repair_brief_if_single_active; then
    ok "work/BRIEF.md: refreshed for single active stream" >&2
    changed=$((changed + 1))
  fi
  printf '%d\n' "$changed"
}
