# -----------------------------------------------------------------------------
# worktree_state.sh — read-only helpers that classify linked git worktrees.
#
# A worktree is classified by what removing it would lose:
#   MISSING   folder is gone (git metadata only; `git worktree prune` fixes it)
#   DIRTY     uncommitted changes
#   UNPUSHED  commits that exist on no remote and are not merged
#   SAFE      clean, nothing unpushed, and merged (or its remote branch is gone)
#   FRESH     clean, no commits of its own yet (just branched, or abandoned)
#   REVIEW    clean but not provably merged (e.g. squash-merged, detached HEAD)
# Only SAFE is ever removed automatically. Pure bash 3.2 + git.
# -----------------------------------------------------------------------------

WT_STATE=""
WT_DETAIL=""

# _wt_main_path [dir] — absolute path of the main checkout for the repo at dir
_wt_main_path() {
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null | awk 'NR==1{print substr($0,10); exit}'
}

# _wt_base_ref <repo> — first existing integration branch
_wt_base_ref() {
  local b
  for b in origin/develop origin/main origin/master develop main master; do
    if git -C "$1" rev-parse -q --verify "$b" >/dev/null 2>&1; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 1
}

# _wt_linked <repo> — "path|branch" per linked (non-main) worktree
_wt_linked() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    BEGIN { RS = ""; FS = "\n" }
    NR > 1 {
      p = ""; b = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^worktree /) p = substr($i, 10)
        if ($i ~ /^branch /)   b = substr($i, 8)
      }
      sub("^refs/heads/", "", b)
      print p "|" b
    }'
}

# _wt_repos [root] — main-checkout paths: every repo directly under root,
# or just the current repo when root is empty.
_wt_repos() {
  local root="${1:-}" d
  if [[ -z "$root" ]]; then
    d="$(_wt_main_path .)"
    [[ -n "$d" ]] && printf '%s\n' "$d"
    return 0
  fi
  for d in "$root"/*/; do
    d="${d%/}"
    [[ -d "$d/.git" ]] && printf '%s\n' "$d"
  done
  return 0
}

# _wt_classify <repo> <path> <branch> — sets WT_STATE and WT_DETAIL
_wt_classify() {
  local repo="$1" path="$2" branch="$3"
  local dirty=0 unpushed=0 base="" merged="no" gone="no" up="" upref="" tip="" basetip=""
  WT_STATE=""
  WT_DETAIL=""

  if [[ ! -d "$path" ]]; then
    WT_STATE="MISSING"; WT_DETAIL="folder gone — run: git worktree prune"
    return 0
  fi
  dirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if (( dirty > 0 )); then
    WT_STATE="DIRTY"; WT_DETAIL="${dirty} uncommitted file(s)"
    return 0
  fi
  if [[ -z "$branch" ]]; then
    WT_STATE="REVIEW"; WT_DETAIL="detached HEAD"
    return 0
  fi

  base="$(_wt_base_ref "$repo" || true)"
  unpushed="$(git -C "$repo" rev-list --count "$branch" --not --remotes 2>/dev/null || echo 0)"
  up="$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)"
  [[ "$up" == *gone* ]] && gone="yes"
  upref="$(git -C "$repo" for-each-ref --format='%(upstream)' "refs/heads/$branch" 2>/dev/null)"
  if [[ -n "$base" ]]; then
    tip="$(git -C "$repo" rev-parse "$branch" 2>/dev/null)"
    basetip="$(git -C "$repo" rev-parse "$base" 2>/dev/null)"
    # An ancestor of base is merged. When tip == base tip the branch is either
    # brand new or was pushed and fast-forwarded. `worktree add -b <b> origin/x`
    # sets the upstream to the BASE, so only an upstream with the branch's own
    # name (<remote>/<branch>) proves it was pushed.
    if git -C "$repo" merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
      if [[ "$tip" != "$basetip" || "$upref" == */"$branch" ]]; then merged="yes"; fi
    fi
  fi

  if [[ "$unpushed" != "0" && "$merged" == "no" ]]; then
    WT_STATE="UNPUSHED"; WT_DETAIL="${unpushed} commit(s) on no remote"
  elif [[ "$merged" == "yes" ]]; then
    WT_STATE="SAFE"; WT_DETAIL="merged into ${base}"
  elif [[ "$gone" == "yes" ]]; then
    WT_STATE="SAFE"; WT_DETAIL="remote branch deleted"
  elif [[ -n "$base" && "$tip" == "$basetip" ]]; then
    WT_STATE="FRESH"; WT_DETAIL="no commits of its own"
  else
    WT_STATE="REVIEW"; WT_DETAIL="not provably merged"
  fi
}

# _wt_size_mb <path> — disk usage in MB (0 when the folder is gone)
_wt_size_mb() {
  local kb
  kb="$(du -sk "$1" 2>/dev/null | awk '{print $1}')"
  printf '%s' "$(( ${kb:-0} / 1024 ))"
}
