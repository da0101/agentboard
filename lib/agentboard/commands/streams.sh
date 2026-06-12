cmd_new_domain() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: ab new-domain <domain-slug> [repo-id ...] [--repo <repo-id>]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug must be kebab-case."

  local -a repo_ids=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ -n "${2:-}" ]] || die "new-domain requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      *)
        repo_ids+=("$1")
        shift
        ;;
    esac
  done
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  local repo_ids_text repo_id repo_ids_literal
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  local template="./.platform/domains/TEMPLATE.md"
  local target="./.platform/domains/${slug}.md"

  [[ -f "$template" ]] || die "$template not found. Update ab templates first."
  [[ ! -e "$target" ]] || die "$target already exists."

  mkdir -p "./.platform/domains"
  cp "$template" "$target"
  replace_template_literals "$target" \
    "<domain-slug>" "$slug" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$target" "repo_ids" "$repo_ids_literal"

  ok "Created domain: .platform/domains/${slug}.md"
}

cmd_new_stream() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: ab new-stream <stream-slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local -a domain_slugs=()
  local stream_type="feature"
  local agent_owner="codex"
  local -a repo_ids=()
  local base_branch="" git_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --domain"
        domain_slugs+=("$2")
        shift 2
        ;;
      --type)
        stream_type="${2:-}"
        shift 2
        ;;
      --agent)
        agent_owner="${2:-}"
        shift 2
        ;;
      --repo)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      --base-branch)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --base-branch"
        base_branch="$2"
        shift 2
        ;;
      --branch)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --branch"
        git_branch="$2"
        shift 2
        ;;
      *)
        die "Unknown flag for new-stream: $1"
        ;;
    esac
  done

  ((${#domain_slugs[@]})) || die "new-stream requires at least one --domain <domain-slug>"
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  # ── Branch resolution ────────────────────────────────────────────────────
  if [[ -z "$base_branch" || -z "$git_branch" ]]; then
    local _current_branch _default_base _branch_prefix _default_branch
    _current_branch="$(git -C . rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    case "$stream_type" in
      hotfix)
        _default_base="master"
        _branch_prefix="hotfix"
        ;;
      bug|bugfix)
        _default_base="develop"
        _branch_prefix="bugfix"
        ;;
      *)
        _default_base="develop"
        _branch_prefix="feature"
        ;;
    esac
    _default_branch="${_branch_prefix}/${slug}"

    if [[ -t 0 ]]; then
      # Interactive: ask the user
      printf '\n  %s?%s %sBranch context for stream %s"%s"%s\n' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET" "$slug" "$C_RESET" >&2
      [[ -n "$_current_branch" ]] && \
        printf '    %sCurrent branch: %s%s\n' "$C_DIM" "$_current_branch" "$C_RESET" >&2
      [[ -z "$base_branch" ]] && \
        base_branch="$(ask "Base branch to fork from" "$_default_base")"
      [[ -z "$git_branch" ]] && \
        git_branch="$(ask "New git branch name for this stream" "$_default_branch")"
    else
      # Non-interactive: follow Git Flow branch policy regardless of current checkout.
      [[ -z "$base_branch" ]] && base_branch="$_default_base"
      [[ -z "$git_branch" ]] && git_branch="$_default_branch"
    fi
  fi

  local stream_template="./.platform/work/TEMPLATE.md"
  local stream_target="./.platform/work/${slug}.md"
  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"
  local project_name
  project_name="$(basename "$(pwd)")"

  [[ -f "$stream_template" ]] || die "$stream_template not found."
  [[ -f "$active" ]] || die "$active not found."
  [[ ! -e "$stream_target" ]] || die "$stream_target already exists."

  local domain_slugs_text domain_slug domain_file
  domain_slugs_text="$(printf '%s\n' "${domain_slugs[@]}" | unique_nonempty_lines)"
  while IFS= read -r domain_slug; do
    [[ -n "$domain_slug" ]] || continue
    [[ "$domain_slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug '$domain_slug' must be kebab-case."
    domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || die "$domain_file does not exist. Create the domain first."
  done <<< "$domain_slugs_text"

  local repo_ids_text repo_id
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"

  local domain_slugs_literal repo_ids_literal
  domain_slugs_literal="$(frontmatter_inline_array <<< "$domain_slugs_text")"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  cp "$stream_template" "$stream_target"
  replace_template_literals "$stream_target" \
    "<stream-slug>" "$slug" \
    "type: feature" "type: $stream_type" \
    "agent_owner: claude-code" "agent_owner: $agent_owner" \
    "status: planning" "status: planning" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$stream_target" "domain_slugs" "$domain_slugs_literal"
  replace_frontmatter_line "$stream_target" "repo_ids" "$repo_ids_literal"
  replace_frontmatter_line "$stream_target" "base_branch" "$base_branch"
  replace_frontmatter_line "$stream_target" "git_branch" "$git_branch"

  local row="| $slug | $stream_type | planning | $agent_owner | $(today) |"
  if ! grep -qF "| _(none)_ | — | — | — | — |" "$active" && grep -qF "| $slug |" "$active"; then
    die "work/ACTIVE.md already has a row for '$slug'"
  fi
  # Lock the ACTIVE.md read-modify-write so concurrent ab processes
  # (e.g. another new-stream or a close) can't clobber each other's rows.
  platform_lock_acquire "active-md" || true
  if grep -qF "| _(none)_ | — | — | — | — |" "$active"; then
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      $0 == "| _(none)_ | — | — | — | — |" { print row; next }
      { print }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  else
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      /^\|---/ { in_table=1; print; next }
      in_table && /^\|/ { print; next }
      in_table && !inserted { print row; inserted=1; in_table=0 }
      { print }
      END {
        if (!inserted) print row
      }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  fi
  platform_lock_release "active-md"

  if brief_is_placeholder "$brief" || [[ -z "$(brief_primary_stream_slug 2>/dev/null || true)" ]]; then
    write_brief_stub "$brief" "$project_name" "$slug" "$domain_slugs_text" "planning"
    ok "Updated work/BRIEF.md with a starter brief"
  else
    warn "work/BRIEF.md already has content. Stream created, but BRIEF.md was left untouched."
  fi

  ok "Created stream: .platform/work/${slug}.md"
  ok "Registered stream in .platform/work/ACTIVE.md"
}
