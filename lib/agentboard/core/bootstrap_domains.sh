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

