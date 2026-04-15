# -----------------------------------------------------------------------------
# Colors (honors NO_COLOR, disables if stdout isn't a TTY)
# -----------------------------------------------------------------------------

if [[ -n "${NO_COLOR:-}" ]] || ! [[ -t 1 ]]; then
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
else
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
bold() { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
head() { printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '  %s●%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '  %s✖%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ask <prompt> [default] [hint]
# Prints hint (if given) on its own dim line, then the prompt with the default
# shown in [brackets]. Returns the user input (or default) on stdout.
ask() {
  local prompt="$1" default="${2:-}" hint="${3:-}" reply
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  if [[ -n "$default" ]]; then
    printf '  %s?%s %s%s%s %s[%s]%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$default" "$C_RESET" >&2
    read -r reply
    echo "${reply:-$default}"
  else
    printf '  %s?%s %s%s%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" >&2
    read -r reply
    echo "$reply"
  fi
}

ask_yes_no() {
  local prompt="$1" reply
  printf '  %s?%s %s%s%s %s[y/N]%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ask_yes_no_default <prompt> <default: Y|N> [hint]
# Same styling as ask_yes_no but with a configurable default. An empty reply
# returns the default. Supports a dim-line hint printed above the prompt.
ask_yes_no_default() {
  local prompt="$1" default="${2:-N}" hint="${3:-}" reply bracket
  if [[ "$default" =~ ^[Yy]$ ]]; then
    bracket="[Y/n]"
  else
    bracket="[y/N]"
  fi
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  printf '  %s?%s %s%s%s %s%s%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$bracket" "$C_RESET" >&2
  read -r reply
  if [[ -z "$reply" ]]; then
    [[ "$default" =~ ^[Yy]$ ]]
  else
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

today() { date +%F; }

require_templates() {
  [[ -d "$TEMPLATES_PLATFORM" ]] || die "templates/platform/ not found at $TEMPLATES_PLATFORM"
}

substitute() {
  # substitute <file> KEY1 value1 KEY2 value2 ...
  local file="$1"; shift
  local key value value_esc
  while [[ $# -gt 0 ]]; do
    key="$1"; value="$2"; shift 2
    value_esc="${value//|/\\|}"
    sed -i.bak "s|{{${key}}}|${value_esc}|g" "$file"
    rm -f "${file}.bak"
  done
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

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

normalize_kebab_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  printf '%s' "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
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
  local -a items
  IFS=',' read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && printf '%s\n' "$item"
  done
}

is_placeholder_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  [[ "$value" == "—" ]] && return 0
  [[ "$value" == "YYYY-MM-DD" ]] && return 0
  [[ "$value" =~ \<.*\> ]] && return 0
  [[ "$value" =~ _TODO_ ]] && return 0
  [[ "$value" =~ ^TBD ]] && return 0
  return 1
}

replace_template_literals() {
  local file="$1"; shift
  local old new new_esc
  while [[ $# -gt 0 ]]; do
    old="$1"; new="$2"; shift 2
    new_esc="${new//|/\\|}"
    sed -i.bak "s|$old|$new_esc|g" "$file"
  done
  rm -f "${file}.bak"
}

replace_frontmatter_line() {
  local file="$1" key="$2" value="$3"
  sed -i.bak -E "s|^${key}: .*|${key}: ${value}|" "$file"
  rm -f "${file}.bak"
}

unique_nonempty_lines() {
  awk 'NF && !seen[$0]++'
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

join_lines_comma() {
  awk 'NF { out = out ? out ", " $0 : $0 } END { print out }'
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

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

detect_shell_name() {
  local shell_path="${SHELL:-}"
  shell_path="${shell_path##*/}"
  case "$shell_path" in
    zsh|bash|fish) printf '%s\n' "$shell_path" ;;
    *) printf '%s\n' "zsh" ;;
  esac
}

default_user_bin_dir() {
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    printf '%s\n' "$XDG_BIN_HOME"
  elif [[ -d "$HOME/.local/bin" ]]; then
    printf '%s\n' "$HOME/.local/bin"
  elif [[ -d "$HOME/bin" ]]; then
    printf '%s\n' "$HOME/bin"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

shell_rc_file() {
  local shell_name="$1"
  case "$shell_name" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

shell_path_snippet() {
  local shell_name="$1" bin_dir="$2"
  case "$shell_name" in
    fish) printf 'fish_add_path "%s"\n' "$bin_dir" ;;
    *) printf 'export PATH="%s:$PATH"\n' "$bin_dir" ;;
  esac
}

path_contains_dir() {
  local dir="$1" entry
  IFS=':' read -r -a entries <<< "${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ "$entry" == "$dir" ]] && return 0
  done
  return 1
}

ignore_bootstrap_domain_slug() {
  local slug="$1"
  case "$slug" in
    api|apis|app|apps|backend|frontend|mobile|web|site|core|common|shared|lib|libs|utils|util|helpers|helper| \
    component|components|page|pages|screen|screens|hook|hooks|model|models|service|services|store|stores| \
    state|types|generated|assets|styles|theme|themes|public|static|vendor|config|configs|script|scripts| \
    docs|doc|test|tests|spec|specs|fixture|fixtures|example|examples|sample|samples|android|ios|macos|windows|linux| \
    package|packages|sdk|sdks|contract|contracts|client|clients|proto|protos|schema|schemas|migration|migrations| \
    build|dist|coverage|storybook|stories|workspace|workspaces|feature|features|domain|domains|module|modules)
      return 0
      ;;
  esac
  return 1
}

dir_has_project_content() {
  local dir="$1"
  find "$dir" -mindepth 1 -maxdepth 2 \( -type f -o -type d \) ! -name '.DS_Store' 2>/dev/null | grep -q .
}

repo_feature_dir_candidates() {
  local repo_path="$1"
  local candidate base slug
  for candidate in \
    "$repo_path/src/features"/* \
    "$repo_path/src/modules"/* \
    "$repo_path/src/domains"/* \
    "$repo_path/src/apps"/* \
    "$repo_path/lib/features"/* \
    "$repo_path/lib/modules"/* \
    "$repo_path/lib/domains"/* \
    "$repo_path/lib/screens"/* \
    "$repo_path/src/screens"/* \
    "$repo_path/apps"/* \
    "$repo_path/packages"/* \
    "$repo_path/services"/* \
    "$repo_path/features"/* \
    "$repo_path/domains"/* \
    "$repo_path/modules"/*; do
    [[ -d "$candidate" ]] || continue
    base="$(basename "$candidate")"
    [[ "$base" =~ ^[\[\(\._@] ]] && continue
    dir_has_project_content "$candidate" || continue
    slug="$(slugify "$base")"
    [[ -n "$slug" ]] || continue
    ignore_bootstrap_domain_slug "$slug" && continue
    printf '%s\n' "$slug"
  done
  return 0
}

repo_django_app_candidates() {
  local repo_path="$1"
  local dir base slug
  for dir in "$repo_path"/*; do
    [[ -d "$dir" ]] || continue
    base="$(basename "$dir")"
    [[ "$base" =~ ^[._] ]] && continue
    [[ -f "$dir/apps.py" || -f "$dir/models.py" || -f "$dir/views.py" || -f "$dir/serializers.py" || -f "$dir/urls.py" ]] || continue
    slug="$(slugify "$base")"
    [[ -n "$slug" ]] || continue
    ignore_bootstrap_domain_slug "$slug" && continue
    printf '%s\n' "$slug"
  done
  return 0
}

repo_bootstrap_domain_candidates() {
  local repo_path="$1"
  repo_feature_dir_candidates "$repo_path"
  repo_django_app_candidates "$repo_path"
  return 0
}

infer_bootstrap_domains() {
  local discovered_rows="$1"
  local repo_id repo_path repo_stack repo_ref repo_abs repo_name slug
  while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
    [[ -n "$repo_id" && -n "$repo_abs" ]] || continue
    while IFS= read -r slug; do
      [[ -n "$slug" ]] || continue
      printf '%s|%s\n' "$slug" "$repo_id"
    done < <(repo_bootstrap_domain_candidates "$repo_abs" | unique_nonempty_lines)
  done <<< "$discovered_rows"
  return 0
}

merge_bootstrap_domain_rows() {
  awk -F'|' '
    NF >= 2 {
      key = $1 "|" $2
      if (!seen[key]++) print $1 "|" $2
    }
  '
}

domain_repo_rows() {
  local repos_file="$1"
  local domain_file slug repo_id repo_ids
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    slug="$(basename "$domain_file" .md)"
    if has_frontmatter "$domain_file"; then
      repo_ids="$(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")"
    else
      repo_ids="$(infer_domain_repo_ids "$domain_file" "$repos_file")"
    fi
    while IFS= read -r repo_id; do
      [[ -n "$repo_id" ]] || continue
      printf '%s|%s\n' "$slug" "$repo_id"
    done <<< "$repo_ids"
  done < <(domain_files)
  return 0
}

current_git_branch() {
  local repo_path="$1"
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$repo_path" rev-parse --short HEAD 2>/dev/null || true
}

repo_changed_files() {
  local repo_path="$1"
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$repo_path" status --porcelain --untracked-files=all 2>/dev/null | awk '
    {
      path = $2
      if (path ~ /^\.platform\//) next
      if (path ~ /^\.claude\//) next
      if (path ~ /^\.agents\//) next
      if (path == "CLAUDE.md" || path == "AGENTS.md" || path == "GEMINI.md") next
      print path
    }
  '
  return 0
}

repo_diff_signal_text() {
  local repo_path="$1"
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  {
    git -C "$repo_path" diff --cached --unified=0 --no-color 2>/dev/null || true
    git -C "$repo_path" diff --unified=0 --no-color 2>/dev/null || true
  } | awk '
    function ignore_path(path) {
      return path ~ /^\.platform\// || path ~ /^\.claude\// || path ~ /^\.agents\// || \
             path == "CLAUDE.md" || path == "AGENTS.md" || path == "GEMINI.md"
    }
    /^diff --git / { next }
    /^index / { next }
    /^@@ / { next }
    /^\+\+\+ / {
      path = $2
      sub(/^b\//, "", path)
      skip = ignore_path(path)
      next
    }
    /^--- / {
      path = $2
      sub(/^a\//, "", path)
      skip = ignore_path(path)
      next
    }
    /^[+-]/ {
      if (skip) next
      line = substr($0, 2)
      if (line ~ /^[[:space:]]*$/) next
      print line
    }
  ' | sed -E 's/[^A-Za-z0-9_./ -]+/ /g'
  return 0
}

repo_has_dirty_worktree() {
  local repo_path="$1"
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n "$(git -C "$repo_path" status --porcelain 2>/dev/null)" ]]
}

branch_to_stream_type() {
  local branch_slug="$1"
  case "$branch_slug" in
    fix-*|bug-*|bugfix-*|hotfix-*) printf '%s\n' "bug" ;;
    chore-*|task-*|refactor-*|cleanup-*|spike-*|investigate-*) printf '%s\n' "improvement" ;;
    *) printf '%s\n' "feature" ;;
  esac
}

branch_to_stream_slug() {
  local branch="$1" slug
  slug="$(slugify "$branch")"
  case "$slug" in
    feature-*|feat-*|fix-*|bug-*|bugfix-*|hotfix-*|chore-*|task-*|refactor-*|cleanup-*|spike-*|investigate-*)
      slug="${slug#*-}"
      ;;
  esac
  printf '%s\n' "$slug"
}

is_default_branch_name() {
  local branch="$1"
  case "$branch" in
    main|master|develop|development|dev|staging|stage|production|prod|release)
      return 0
      ;;
  esac
  return 1
}

best_domain_matches_for_stream() {
  local stream_slug="$1" repo_id="$2" domain_rows="$3"
  local best_score=0 score row domain_slug domain_repo matches=""
  while IFS='|' read -r domain_slug domain_repo; do
    [[ -n "$domain_slug" && -n "$domain_repo" ]] || continue
    [[ "$domain_repo" == "$repo_id" ]] || continue
    score="$(score_slug_similarity "$stream_slug" "$domain_slug")"
    if (( score > best_score )); then
      best_score="$score"
      matches="$domain_slug"
    elif (( score > 0 && score == best_score )); then
      matches="${matches}"$'\n'"$domain_slug"
    fi
  done <<< "$domain_rows"
  if (( best_score == 0 )); then
    while IFS='|' read -r domain_slug domain_repo; do
      [[ -n "$domain_slug" ]] || continue
      score="$(score_slug_similarity "$stream_slug" "$domain_slug")"
      if (( score > best_score )); then
        best_score="$score"
        matches="$domain_slug"
      elif (( score > 0 && score == best_score )); then
        matches="${matches}"$'\n'"$domain_slug"
      fi
    done <<< "$domain_rows"
  fi
  if (( best_score > 0 )); then
    printf '%s\n' "$matches" | unique_nonempty_lines
  fi
  return 0
}

best_domain_matches_for_paths() {
  local repo_id="$1" domain_rows="$2" paths="$3"
  local best_score=0 total_score score domain_slug domain_repo path matches=""
  while IFS='|' read -r domain_slug domain_repo; do
    [[ -n "$domain_slug" && -n "$domain_repo" ]] || continue
    [[ "$domain_repo" == "$repo_id" ]] || continue
    total_score=0
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      score="$(score_slug_similarity "$(slugify "$path")" "$domain_slug")"
      total_score=$((total_score + score))
    done <<< "$paths"
    if (( total_score > best_score )); then
      best_score="$total_score"
      matches="$domain_slug"
    elif (( total_score > 0 && total_score == best_score )); then
      matches="${matches}"$'\n'"$domain_slug"
    fi
  done <<< "$domain_rows"
  if (( best_score == 0 )); then
    while IFS='|' read -r domain_slug domain_repo; do
      [[ -n "$domain_slug" ]] || continue
      total_score=0
      while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        score="$(score_slug_similarity "$(slugify "$path")" "$domain_slug")"
        total_score=$((total_score + score))
      done <<< "$paths"
      if (( total_score > best_score )); then
        best_score="$total_score"
        matches="$domain_slug"
      elif (( total_score > 0 && total_score == best_score )); then
        matches="${matches}"$'\n'"$domain_slug"
      fi
    done <<< "$domain_rows"
  fi
  if (( best_score > 0 )); then
    printf '%s\n' "$matches" | unique_nonempty_lines
  fi
  return 0
}

stream_slug_from_domains() {
  local domain_list="$1"
  local first
  first="$(printf '%s\n' "$domain_list" | awk 'NF { print; exit }')"
  [[ -n "$first" ]] || return 0
  printf '%s-worktree\n' "$first"
}

ignore_bootstrap_focus_token() {
  local token="$1"
  case "$token" in
    index|main|app|apps|src|lib|server|client|view|views|screen|screens|page|pages|component|components| \
    hook|hooks|model|models|service|services|store|stores|test|tests|spec|specs|util|utils|helper|helpers| \
    api|types|schema|schemas|feature|features|domain|domains|module|modules|controller|controllers|route|routes| \
    config|configs|package|packages|android|ios|assets|projectsettings|functions|function|common|shared)
      return 0
      ;;
  esac
  return 1
}

bootstrap_focus_token_from_paths() {
  local paths="$1" domain_list="$2"
  local domain_csv line token best="" domain_slug
  domain_csv="$(printf '%s\n' "$domain_list" | join_lines_comma)"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    while IFS= read -r token; do
      [[ -n "$token" ]] || continue
      token="$(slugify "$token")"
      [[ -n "$token" ]] || continue
      ignore_bootstrap_focus_token "$token" && continue
      if printf '%s\n' "$domain_csv" | tr ',' '\n' | grep -Fxq "$token"; then
        continue
      fi
      best="$token"
      break 2
    done < <(printf '%s\n' "$line" | tr '/._-' '\n')
  done <<< "$paths"
  [[ -n "$best" ]] && printf '%s\n' "$best"
}

infer_stream_type_from_diff() {
  local branch_slug="$1" changed_paths="$2" diff_text="$3"
  local haystack
  haystack="$(printf '%s\n%s\n%s\n' "$branch_slug" "$changed_paths" "$diff_text" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$haystack" | grep -Eiq '(^|[^a-z])(fix|fixes|bug|bugs|error|errors|fail|fails|failing|failure|failures|exception|exceptions|crash|crashes|hotfix|null|undefined|regress|regression|broken|retry|guard)([^a-z]|$)'; then
    printf '%s\n' "bug"
  elif printf '%s' "$haystack" | grep -Eiq '(^|[^a-z])(refactor|cleanup|rename|bump|upgrade|lint|format|optimi[sz]e|perf|performance|docs|documentation|chore|reorganize|rework)([^a-z]|$)'; then
    printf '%s\n' "improvement"
  elif [[ -n "$branch_slug" ]]; then
    branch_to_stream_type "$branch_slug"
  else
    printf '%s\n' "feature"
  fi
}

stream_slug_from_context() {
  local domain_list="$1" stream_type="$2" changed_paths="$3" diff_text="$4"
  local first_domain focus_token suffix
  first_domain="$(printf '%s\n' "$domain_list" | awk 'NF { print; exit }')"
  [[ -n "$first_domain" ]] || return 0
  focus_token="$(bootstrap_focus_token_from_paths "$changed_paths" "$domain_list")"
  case "$stream_type" in
    bug) suffix="fix" ;;
    feature) suffix="feature" ;;
    *) suffix="worktree" ;;
  esac
  if [[ -n "$focus_token" ]]; then
    printf '%s-%s-%s\n' "$first_domain" "$focus_token" "$suffix"
  else
    printf '%s-%s\n' "$first_domain" "$suffix"
  fi
}

infer_bootstrap_stream_suggestions() {
  local discovered_rows="$1" domain_rows="$2"
  local repo_id repo_path repo_stack repo_ref repo_abs repo_name branch branch_slug stream_slug stream_type matched_domains changed_paths confidence diff_text
  while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
    [[ -n "$repo_id" && -n "$repo_abs" ]] || continue
    branch="$(current_git_branch "$repo_abs")"
    changed_paths="$(repo_changed_files "$repo_abs")"
    diff_text="$(repo_diff_signal_text "$repo_abs")"
    if [[ -z "$branch" && -z "$changed_paths" ]]; then
      continue
    fi
    if [[ -n "$branch" ]] && ! is_default_branch_name "$branch"; then
      stream_slug="$(branch_to_stream_slug "$branch")"
      stream_type="$(infer_stream_type_from_diff "$(slugify "$branch")" "$changed_paths" "$diff_text")"
      matched_domains="$(best_domain_matches_for_stream "$stream_slug" "$repo_id" "$domain_rows")"
      confidence="medium"
      if [[ -n "$changed_paths" ]]; then
        local changed_domains
        changed_domains="$(best_domain_matches_for_paths "$repo_id" "$domain_rows" "$changed_paths")"
        [[ -n "$changed_domains" ]] && matched_domains="$changed_domains"
        confidence="high"
      fi
    else
      [[ -n "$changed_paths" ]] || continue
      matched_domains="$(best_domain_matches_for_paths "$repo_id" "$domain_rows" "$changed_paths")"
      stream_type="$(infer_stream_type_from_diff "" "$changed_paths" "$diff_text")"
      stream_slug="$(stream_slug_from_context "$matched_domains" "$stream_type" "$changed_paths" "$diff_text")"
      [[ -n "$stream_slug" ]] || stream_slug="$(stream_slug_from_domains "$matched_domains")"
      confidence="medium"
      [[ -n "$diff_text" || "$stream_type" != "feature" ]] && confidence="high"
    fi
    [[ -n "$stream_slug" ]] || continue
    [[ -n "$matched_domains" ]] || continue
    printf '%s|%s|%s|%s|%s|%s\n' "$repo_id" "${branch:-dirty-worktree}" "$stream_slug" "$stream_type" "$(printf '%s' "$matched_domains" | join_lines_comma)" "$confidence"
  done <<< "$discovered_rows"
  return 0
}

create_domain_stub() {
  local slug="$1" repo_ids_text="$2"
  local template="./.platform/domains/TEMPLATE.md"
  local target="./.platform/domains/${slug}.md"
  local repo_ids_literal
  [[ -f "$template" ]] || die "$template not found. Update agentboard templates first."
  [[ ! -e "$target" ]] || return 0
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"
  mkdir -p "./.platform/domains"
  cp "$template" "$target"
  replace_template_literals "$target" \
    "<domain-slug>" "$slug" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$target" "repo_ids" "$repo_ids_literal"
  return 0
}

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

