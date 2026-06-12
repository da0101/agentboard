# `ab watch` — polling/snapshot core: change detection, path ranking,
# dirty-state signatures, and the per-tick auto-checkpoint.

_watch_signature_dir() {
  printf '%s\n' "./.platform/.watch"
}

_watch_signature_file() {
  local stream="$1"
  printf '%s/%s.sig\n' "$(_watch_signature_dir)" "$stream"
}

_watch_path_from_porcelain_line() {
  local line="$1"
  local path=""
  if (( ${#line} > 3 )); then
    path="${line:3}"
  fi
  if [[ "$path" == *" -> "* ]]; then
    path="${path##* -> }"
  fi
  printf '%s\n' "$path"
}

_watch_is_untracked_line() {
  local line="$1"
  [[ "${line:0:2}" == "??" ]]
}

_watch_stream_tokens() {
  local stream="$1"
  printf '%s\n' "$stream" | tr '-' '\n' | awk 'length($0) >= 3 { print }'
}

_watch_path_score() {
  local stream="$1" path="$2"
  local lower_path score=0 token
  lower_path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

  case "$lower_path" in
    ".platform/work/${stream}.md") score=$((score + 80)) ;;
    .platform/work/*) score=$((score + 10)) ;;
    .platform/domains/*) score=$((score + 5)) ;;
    .claude/skills/*|.agents/skills/*|.codex/skills/*) score=$((score - 30)) ;;
    .claude/*|.agents/*|.codex/*) score=$((score - 15)) ;;
    .platform/*) score=$((score - 5)) ;;
    .*) score=$((score - 8)) ;;
  esac

  for token in $(_watch_stream_tokens "$stream"); do
    [[ -n "$token" ]] || continue
    if [[ "$lower_path" == *"$token"* ]]; then
      score=$((score + 25))
    fi
  done

  case "$lower_path" in
    src/*|lib/*|app/*|components/*|pages/*|tests/*|test/*|frontend/*|backend/*)
      score=$((score + 5))
      ;;
  esac

  printf '%s\n' "$score"
}

_watch_rank_paths() {
  local stream="$1"
  shift

  local -a paths=("$@")
  local -a scored=()
  local idx=0 score path

  for path in "${paths[@]}"; do
    score="$(_watch_path_score "$stream" "$path")"
    scored+=("${score}"$'\t'"${idx}"$'\t'"${path}")
    idx=$((idx + 1))
  done

  if (( ${#scored[@]} == 0 )); then
    return 0
  fi

  printf '%s\n' "${scored[@]}" \
    | sort -t "$(printf '\t')" -k1,1nr -k2,2n \
    | awk '{ sub(/^[^\t]*\t[^\t]*\t/, "", $0); print }'
}

_watch_best_path_score() {
  local stream="$1"
  shift

  local -a paths=("$@")
  if (( ${#paths[@]} == 0 )); then
    printf '%s\n' "-999"
    return 0
  fi

  local best score path
  best="$(_watch_path_score "$stream" "${paths[0]}")"
  for path in "${paths[@]}"; do
    score="$(_watch_path_score "$stream" "$path")"
    if (( score > best )); then
      best="$score"
    fi
  done
  printf '%s\n' "$best"
}

_watch_path_state() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'missing\n'
    return 0
  fi

  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f '%m:%z' "$path" 2>/dev/null || printf 'missing\n'
  else
    stat -c '%Y:%s' "$path" 2>/dev/null || printf 'missing\n'
  fi
}

_watch_signature_from_paths() {
  local changes="$1"
  shift

  local -a paths=("$@")
  local limit=0 path
  printf 'changes=%s\n' "$changes"
  for path in "${paths[@]}"; do
    printf '%s|%s\n' "$path" "$(_watch_path_state "$path")"
    limit=$((limit + 1))
    if (( limit >= 8 )); then
      break
    fi
  done
}

_watch_poll_and_checkpoint() {
  local stream="$1" stream_file="$2" threshold="$3" quiet="${4:-0}"

  [[ -f "$stream_file" ]] || return 0
  local status
  status="$(frontmatter_value "$stream_file" "status")"
  case "$status" in done|archived|closed) return 0 ;; esac

  # Skip if stream file was touched in the last 5 minutes (fresh manual checkpoint)
  local mtime now
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime="$(stat -f %m "$stream_file" 2>/dev/null || echo 0)"
  else
    mtime="$(stat -c %Y "$stream_file" 2>/dev/null || echo 0)"
  fi
  now="$(date +%s)"
  if (( now - mtime < 300 )); then
    return 0
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  local porcelain sig_file
  sig_file="$(_watch_signature_file "$stream")"
  porcelain="$(git status --porcelain 2>/dev/null || true)"
  if [[ -z "$porcelain" ]]; then
    rm -f "$sig_file"
    return 0
  fi

  local -a changed_paths=()
  local stream_rel_path=".platform/work/${stream}.md"
  local line path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if _watch_is_untracked_line "$line"; then
      continue
    fi
    path="$(_watch_path_from_porcelain_line "$line")"
    if [[ "$path" == "$stream_rel_path" ]]; then
      continue
    fi
    [[ -n "$path" ]] && changed_paths+=("$path")
  done <<< "$porcelain"

  local changes
  changes="${#changed_paths[@]}"
  [[ -z "$changes" ]] && changes=0
  if (( changes < threshold )); then
    rm -f "$sig_file"
    return 0
  fi

  local -a ranked_paths=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && ranked_paths+=("$path")
  done < <(_watch_rank_paths "$stream" "${changed_paths[@]}")

  local files focus prev_next what ts current_sig previous_sig count top_score
  files=""
  count=0
  for path in "${ranked_paths[@]}"; do
    if [[ -z "$files" ]]; then
      files="$path"
    else
      files="${files}, ${path}"
    fi
    count=$((count + 1))
    if (( count >= 5 )); then
      break
    fi
  done
  focus="${ranked_paths[0]:-}"
  top_score="$(_watch_best_path_score "$stream" "${ranked_paths[@]}")"
  if (( top_score < 0 )); then
    return 0
  fi
  current_sig="$(_watch_signature_from_paths "$changes" "${ranked_paths[@]}")"
  # Lock the snapshot compare-and-write so two concurrent polls (e.g. a manual
  # `ab watch --once` racing the scheduled one) can't both pass the dedupe
  # check and write duplicate checkpoints. The nested cmd_checkpoint call
  # takes its own "stream-<slug>" lock — different name, no deadlock.
  platform_lock_acquire "watch-${stream}" || true
  previous_sig="$(cat "$sig_file" 2>/dev/null || true)"
  if [[ -n "$previous_sig" && "$previous_sig" == "$current_sig" ]]; then
    platform_lock_release "watch-${stream}"
    return 0
  fi

  prev_next="$(stream_resume_field "$stream_file" "Next action" 2>/dev/null || true)"
  [[ -z "$prev_next" || "$prev_next" == "_not set_" ]] && prev_next="(continue — auto-watch update)"
  ts="$(date '+%H:%M')"
  what="(auto-watch) ${changes} file(s) modified since ${ts}: ${files}"

  if cmd_checkpoint "$stream" \
      --what "$what" \
      --next "$prev_next" \
      --focus "${focus:-—}" >/dev/null 2>&1; then
    mkdir -p "$(_watch_signature_dir)"
    printf '%s\n' "$current_sig" > "$sig_file"
    platform_lock_release "watch-${stream}"
    if (( ! quiet )); then
      printf '%s[watch %s] checkpoint: %s%s\n' "$C_DIM" "$ts" "$what" "$C_RESET" >&2
    fi
    return 0
  fi
  platform_lock_release "watch-${stream}"
  return 1
}
