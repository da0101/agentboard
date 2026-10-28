# -----------------------------------------------------------------------------
# ab worktree status|clean|new — worktrees on demand, never left to rot.
#
#   status [--root DIR] [--fetch]          classify every linked worktree
#   clean  [--root DIR] [--fetch] [--apply] remove SAFE worktrees (dry-run default)
#   new    <slug> [--type T] [--base REF]  create ../<repo>-<slug> on <type>/<slug>
#
# Only worktrees classified SAFE (see worktree_state.sh) are ever removed, and
# removal never uses --force. Pure bash 3.2 + git.
# -----------------------------------------------------------------------------

worktree_usage() {
  cat <<'EOF'
Usage: ab worktree status [--root DIR] [--fetch]
       ab worktree clean  [--root DIR] [--fetch] [--apply]
       ab worktree new <slug> [--type feature|bugfix|hotfix] [--base REF]
       ab worktree list

Worktrees are on demand: create one only when asked, or when two sessions must
edit the same repo at once. Otherwise branch in the main checkout.

  status   one row per linked worktree: SAFE, FRESH, REVIEW, UNPUSHED, DIRTY,
           MISSING. --root DIR scans every repo directly under DIR.
  clean    removes SAFE worktrees (clean, nothing unpushed, merged or remote
           branch deleted) and their merged branches. Dry-run unless --apply.
           Dirty, unpushed, fresh and unproven worktrees are never touched.
  new      git worktree add ../<repo>-<slug> -b <type>/<slug> from the base.
  --fetch  run `git fetch --prune` first so merge state is current.
EOF
}

# _wt_collect_rows <root> <fetch> — prints "repo|path|branch|state|mb|detail"
_wt_collect_rows() {
  local root="$1" fetch="$2" repo line path branch mb
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    (( fetch )) && git -C "$repo" fetch --prune --quiet 2>/dev/null || true
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      path="${line%%|*}"
      branch="${line#*|}"
      _wt_classify "$repo" "$path" "$branch"
      mb="$(_wt_size_mb "$path")"
      printf '%s|%s|%s|%s|%s|%s\n' "$(basename "$repo")" "$path" "${branch:-(detached)}" \
        "$WT_STATE" "$mb" "$WT_DETAIL"
    done < <(_wt_linked "$repo")
  done < <(_wt_repos "$root")
}

# _wt_parse_scan_flags <args...> — sets WT_ROOT, WT_FETCH, WT_APPLY
_wt_parse_scan_flags() {
  WT_ROOT=""; WT_FETCH=0; WT_APPLY=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        [[ -n "${2:-}" && -d "${2:-}" ]] || die "--root needs an existing directory"
        WT_ROOT="$2"; shift 2 ;;
      --fetch) WT_FETCH=1; shift ;;
      --apply) WT_APPLY=1; shift ;;
      -h|--help) worktree_usage; exit 0 ;;
      *) die "Unknown flag for worktree: $1" ;;
    esac
  done
}

cmd_worktree_status() {
  _wt_parse_scan_flags "$@"
  local rows row repo path branch state mb detail safe_mb=0 safe_n=0 total=0
  rows="$(_wt_collect_rows "$WT_ROOT" "$WT_FETCH")"
  if [[ -z "$rows" ]]; then
    say "No linked worktrees."
    return 0
  fi
  printf '  %s%-20s %-38s %-9s %6s  %s%s\n' "$C_DIM" "REPO" "BRANCH" "STATE" "MB" "DETAIL" "$C_RESET"
  while IFS= read -r row; do
    IFS='|' read -r repo path branch state mb detail <<< "$row"
    printf '  %-20s %-38s %-9s %6s  %s\n' "${repo:0:20}" "${branch:0:38}" "$state" "$mb" "$detail"
    total=$((total + 1))
    if [[ "$state" == "SAFE" ]]; then
      safe_n=$((safe_n + 1))
      safe_mb=$((safe_mb + mb))
    fi
  done <<< "$rows"
  printf '\n  %d worktree(s); %d SAFE to remove (%d MB). Run: ab worktree clean%s --apply\n' \
    "$total" "$safe_n" "$safe_mb" "${WT_ROOT:+ --root $WT_ROOT}"
}

cmd_worktree_clean() {
  _wt_parse_scan_flags "$@"
  local rows row repo path branch state mb detail main here freed=0 removed=0 would=0
  here="$(pwd -P)"
  rows="$(_wt_collect_rows "$WT_ROOT" "$WT_FETCH")"
  if [[ -z "$rows" ]]; then
    say "No linked worktrees."
    return 0
  fi
  while IFS= read -r row; do
    IFS='|' read -r repo path branch state mb detail <<< "$row"
    [[ "$state" == "SAFE" ]] || continue
    case "$here/" in "$path"/*) warn "$repo $branch: you are inside it — skipped"; continue ;; esac
    if (( ! WT_APPLY )); then
      say "  would remove  $repo  $branch  (${mb} MB, $detail)"
      would=$((would + 1)); freed=$((freed + mb))
      continue
    fi
    main="$(_wt_main_path "$path")"
    if git -C "$main" worktree remove "$path" 2>/dev/null; then
      ok "removed $repo $branch (${mb} MB)"
      git -C "$main" branch -d "$branch" >/dev/null 2>&1 || dim "    branch kept: git does not see it as fully merged"
      removed=$((removed + 1)); freed=$((freed + mb))
    else
      warn "$repo $branch: git refused to remove it — left in place"
    fi
  done <<< "$rows"
  if (( WT_APPLY )); then
    say "  Removed ${removed} worktree(s), freed ${freed} MB."
  else
    say "  ${would} worktree(s) would be removed (${freed} MB). Re-run with --apply."
  fi
}

cmd_worktree_new() {
  local slug="${1:-}" kind="feature" base="" repo target branch name
  [[ -n "$slug" && "${slug:0:1}" != "-" ]] || die "Usage: ab worktree new <slug> [--type feature|bugfix|hotfix] [--base REF]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Worktree slug must be kebab-case."
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) kind="${2:-}"; shift 2 ;;
      --base) base="${2:-}"; shift 2 ;;
      *) die "Unknown flag for worktree new: $1" ;;
    esac
  done
  case "$kind" in feature|bugfix|hotfix) ;; *) die "--type must be feature, bugfix or hotfix" ;; esac

  repo="$(_wt_main_path .)"
  [[ -n "$repo" ]] || die "Not inside a git repository."
  if [[ -z "$base" ]]; then
    if [[ "$kind" == "hotfix" ]]; then
      base="origin/master"
      git -C "$repo" rev-parse -q --verify "$base" >/dev/null 2>&1 || base="$(_wt_base_ref "$repo" || true)"
    else
      base="$(_wt_base_ref "$repo" || true)"
    fi
  fi
  [[ -n "$base" ]] || die "No develop/main/master base found. Pass --base REF."

  branch="${kind}/${slug}"
  name="$(basename "$repo")-${slug}"
  target="$(dirname "$repo")/${name}"
  [[ ! -e "$target" ]] || die "$target already exists."

  if git -C "$repo" rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    git -C "$repo" worktree add "$target" "$branch" >/dev/null 2>&1 || die "git worktree add failed for existing branch $branch"
  else
    git -C "$repo" worktree add -b "$branch" "$target" "$base" >/dev/null 2>&1 || die "git worktree add failed (base: $base)"
  fi
  ok "Created $target on $branch (from $base)"
  dim "  Record it in the stream file under '## Worktree / Local environment'."
  dim "  When merged: ab worktree clean --apply"
}
