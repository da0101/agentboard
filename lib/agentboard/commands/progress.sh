_progress_json_escape() {
  # Emit a JSON-safe double-quoted string for an arbitrary bash value.
  # Handles \, ", newline, carriage-return, and tab. Pure awk — no jq needed.
  local value="$1"
  printf '%s' "$value" | awk '
    BEGIN { printf "\"" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\r/, "\\r", s)
      gsub(/\t/, "\\t", s)
      if (NR > 1) printf "\\n"
      printf "%s", s
    }
    END { printf "\"" }
  '
}

_progress_emit_json() {
  # _progress_emit_json <status> <slug> <stream_file> <base_ref> <head_branch> <ts> <note> <diff_stat> <dry_run>
  local status="$1" slug="$2" stream_file="$3" base_ref="$4" head_branch="$5"
  local ts="$6" note="$7" diff_stat="$8" dry_run_flag="$9"

  local j_status j_stream j_file j_base j_head j_ts j_note j_stat
  j_status="$(_progress_json_escape "$status")"
  j_stream="$(_progress_json_escape "$slug")"
  j_file="$(_progress_json_escape "$stream_file")"
  j_base="$(_progress_json_escape "$base_ref")"
  j_head="$(_progress_json_escape "$head_branch")"

  if [[ -n "$ts" ]]; then
    j_ts="$(_progress_json_escape "$ts")"
  else
    j_ts="null"
  fi

  if [[ -n "$note" ]]; then
    j_note="$(_progress_json_escape "$note")"
  else
    j_note="null"
  fi

  if [[ -n "$diff_stat" ]]; then
    j_stat="$(_progress_json_escape "$diff_stat")"
  else
    j_stat="null"
  fi

  printf '{"status":%s,"stream":%s,"stream_file":%s,"base_ref":%s,"head_branch":%s,"timestamp":%s,"note":%s,"diff_stat":%s,"dry_run":%s}\n' \
    "$j_status" "$j_stream" "$j_file" "$j_base" "$j_head" "$j_ts" "$j_note" "$j_stat" "$dry_run_flag"
}

cmd_progress() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: ab progress <stream-slug> [--base <branch>] [--note \"<text>\"] [--dry-run] [--json]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local base_override="" note="" dry_run=0 json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        [[ -n "${2:-}" ]] || die "progress requires a value after --base"
        base_override="$2"; shift 2 ;;
      --note)
        [[ -n "${2:-}" ]] || die "progress requires a value after --note"
        note="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --json)    json=1; shift ;;
      *) die "Unknown flag for progress: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (ab new-stream)."

  git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside a git repository. 'ab progress' needs git to compute the diff."

  local base_branch
  if [[ -n "$base_override" ]]; then
    base_branch="$base_override"
  else
    base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  fi
  if is_placeholder_value "$base_branch" || [[ -z "$base_branch" ]]; then
    die "No base branch recorded in $stream_file. Pass --base <branch> or set base_branch in the stream frontmatter."
  fi

  local base_ref=""
  if git rev-parse --verify --quiet "$base_branch" >/dev/null; then
    base_ref="$base_branch"
  elif git rev-parse --verify --quiet "origin/$base_branch" >/dev/null; then
    base_ref="origin/$base_branch"
    warn "Local branch '$base_branch' not found; using 'origin/$base_branch'."
  else
    die "Base branch '$base_branch' not found locally or on origin."
  fi

  local head_branch
  head_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'HEAD')"

  local stat_raw stat_block
  stat_raw="$(git diff --stat "$base_ref"...HEAD 2>/dev/null || true)"
  if [[ -z "$(printf '%s' "$stat_raw" | tr -d ' \t\n')" ]]; then
    if (( json )); then
      _progress_emit_json "no_changes" "$slug" "$stream_file" "$base_ref" "$head_branch" "" "" "" "false"
    else
      ok "No changes on $head_branch vs $base_ref — nothing to record."
    fi
    return 0
  fi
  stat_block="$(printf '%s\n' "$stat_raw" | sed 's/^/    /')"

  local ts block
  ts="$(date '+%Y-%m-%d %H:%M')"
  block="${ts} — diff ${head_branch} vs ${base_ref}"$'\n'"${stat_block}"
  if [[ -n "$note" ]]; then
    block="${block}"$'\n'"    note: ${note}"
  fi

  if (( dry_run )); then
    if (( json )); then
      _progress_emit_json "dry_run" "$slug" "$stream_file" "$base_ref" "$head_branch" "$ts" "$note" "$stat_raw" "true"
    else
      printf '%sWould append to %s → ## Progress log:%s\n\n' "$C_BOLD" "$stream_file" "$C_RESET"
      printf '%s\n' "$block"
    fi
    return 0
  fi

  grep -q '^## Progress log[[:space:]]*$' "$stream_file" \
    || die "$stream_file has no '## Progress log' section. Is this a v1 stream file?"

  local tmp block_file
  tmp="$(mktemp)"
  block_file="$(mktemp)"
  printf '%s\n' "$block" > "$block_file"

  awk -v block_file="$block_file" '
    BEGIN { in_log = 0; inserted = 0 }
    /^## Progress log[[:space:]]*$/ { in_log = 1; print; next }
    in_log && /^## / && !inserted {
      while ((getline line < block_file) > 0) print line
      close(block_file)
      print ""
      inserted = 1
      in_log = 0
      print
      next
    }
    { print }
    END {
      if (in_log && !inserted) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
    }
  ' "$stream_file" > "$tmp"

  rm -f "$block_file"
  mv "$tmp" "$stream_file"

  local today_str
  today_str="$(today)"
  if has_frontmatter "$stream_file"; then
    replace_frontmatter_line "$stream_file" "updated_at" "$today_str"
  fi

  if (( json )); then
    _progress_emit_json "appended" "$slug" "$stream_file" "$base_ref" "$head_branch" "$ts" "$note" "$stat_raw" "false"
  else
    ok "Appended progress block to $stream_file"
  fi
}
