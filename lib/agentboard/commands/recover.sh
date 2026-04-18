cmd_recover() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      _recover_print_help
      return 0
    fi
    die "Usage: agentboard recover <stream-slug> [--confirm] [--since <ref>]"
  fi
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local confirm=0 since_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      --since)
        [[ -n "${2:-}" ]] || die "recover requires a value after --since"
        since_override="$2"; shift 2 ;;
      -h|--help) _recover_print_help; return 0 ;;
      *) die "Unknown flag for recover: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."
  has_frontmatter "$stream_file" \
    || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  git rev-parse --git-dir >/dev/null 2>&1 \
    || die "Not inside a git repository. 'agentboard recover' needs git log."

  local updated_at head_branch
  updated_at="$(frontmatter_value "$stream_file" "updated_at")"
  head_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'HEAD')"

  local since_arg=""
  if [[ -n "$since_override" ]]; then
    since_arg="--since=$since_override"
  elif [[ -n "$updated_at" ]] && ! is_placeholder_value "$updated_at"; then
    since_arg="--since=$updated_at"
  fi

  local commits=""
  if [[ -n "$since_arg" ]]; then
    commits="$(git log --oneline "$since_arg" 2>/dev/null || true)"
  else
    commits="$(git log --oneline -10 2>/dev/null || true)"
  fi

  if [[ -z "$(printf '%s' "$commits" | tr -d ' \t\n')" ]]; then
    ok "No new commits since last checkpoint (${updated_at:-unknown}). Nothing to recover."
    say "  ${C_DIM}If context was lost mid-session, run 'agentboard checkpoint ${slug} --what ... --next ...' manually.${C_RESET}"
    return 0
  fi

  local commit_count first_hash first_msg
  commit_count="$(printf '%s\n' "$commits" | awk 'NF { c++ } END { print c + 0 }')"
  first_hash="$(printf '%s\n' "$commits" | awk 'NR==1' | awk '{print $1}')"
  first_msg="$(printf '%s\n' "$commits" | awk 'NR==1' | cut -d' ' -f2-)"

  local what next
  what="recovered ${commit_count} commit(s) since ${updated_at:-start} on ${head_branch} — latest: ${first_hash}: ${first_msg}"
  next="review git log --oneline ${since_arg:---10} and set a concrete next action"

  printf '\n%s%sagentboard recover%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  stream: %s%s%s\n' "$C_BOLD" "$slug" "$C_RESET"
  printf '  branch: %s\n' "$head_branch"
  printf '  since:  %s\n' "${updated_at:-(no recorded checkpoint)}"
  say
  printf '%sCommits to record:%s\n' "$C_BOLD" "$C_RESET"
  printf '%s\n' "$commits" | sed 's/^/  /'
  say
  printf '%sCheckpoint to write:%s\n' "$C_BOLD" "$C_RESET"
  printf '  what: %s\n' "$what"
  printf '  next: %s\n' "$next"
  say

  if (( ! confirm )); then
    printf '%sPreview only. Re-run with --confirm to write this recovery checkpoint.%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  cmd_checkpoint "$slug" --what "$what" --next "$next"
}

_recover_print_help() {
  cat <<'EOF'
Usage: agentboard recover <stream-slug> [--confirm] [--since <ref>]

Reconstruct a checkpoint from git commit history when context was lost
without a manual checkpoint. Scans commits on the current branch since the
stream's last `updated_at` and writes a recovery entry summarizing them.

This is the self-healing step for the "agent lost context and didn't
checkpoint" scenario. Use it when `agentboard brief` shows a stream as
stale but git has new commits.

Flags:
  --confirm        Actually write the checkpoint. Default is preview-only.
  --since <ref>    Override the default range (git date or hash).

Companion to `checkpoint --auto` (which auto-saves on every commit via the
post-commit hook). Use `recover` when commits exist but the stream file is
still stale — e.g. if the post-commit hook wasn't installed.
EOF
}
