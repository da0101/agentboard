cmd_add_repo() {
  local template_dir="./.platform/templates/repo"
  [[ -d "$template_dir" ]] || die "$template_dir not found. add-repo requires a multi-repo project."
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || die "Usage: agentboard add-repo <path-to-repo>"
  [[ -d "$repo_path" ]] || die "$repo_path does not exist"

  local existing=""
  local entry
  for entry in CLAUDE.md AGENTS.md GEMINI.md; do
    if [[ -e "$repo_path/$entry" ]]; then
      existing="${existing:+$existing, }$entry"
    fi
  done
  [[ -z "$existing" ]] || die "$repo_path already has root entry files ($existing). add-repo will not overwrite them."

  say "See .platform/templates/repo/ADDING-A-REPO.md for the full runbook."
  say "Copying entry file templates to $repo_path..."
  cp "$template_dir/CLAUDE.md.template" "$repo_path/CLAUDE.md"
  cp "$template_dir/AGENTS.md.template" "$repo_path/AGENTS.md"
  cp "$template_dir/GEMINI.md.template" "$repo_path/GEMINI.md"
  ok "Copied CLAUDE.md / AGENTS.md / GEMINI.md to $repo_path"
  say "Now fill in the placeholders and add the repo path to .platform/scripts/sync-context.sh REPOS=() array."
  say "Or: tell your LLM 'onboard this new repo into the platform' and let it do the fill pass."
}

cmd_install() {
  local bin_dir="" shell_name="" dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ -n "${2:-}" ]] || die "install requires a value after --dir"
        bin_dir="$2"
        shift 2
        ;;
      --shell)
        [[ -n "${2:-}" ]] || die "install requires a value after --shell"
        shell_name="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      *)
        die "Usage: agentboard install [--dir <bin-dir>] [--shell zsh|bash|fish] [--dry-run]"
        ;;
    esac
  done

  [[ -n "${HOME:-}" ]] || die "HOME is not set."
  [[ -n "$bin_dir" ]] || bin_dir="$(default_user_bin_dir)"
  [[ -n "$shell_name" ]] || shell_name="$(detect_shell_name)"
  case "$shell_name" in
    zsh|bash|fish) ;;
    *) die "Unsupported shell '$shell_name'. Use zsh, bash, or fish." ;;
  esac

  local source_bin install_path rc_file path_snippet
  source_bin="$AGENTBOARD_ROOT/bin/agentboard"
  install_path="$bin_dir/agentboard"
  rc_file="$(shell_rc_file "$shell_name")"
  path_snippet="$(shell_path_snippet "$shell_name" "$bin_dir")"

  printf '\n%s%sagentboard install%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if (( dry_run )); then
    printf '%sDry-run mode — no files will be changed.%s\n' "$C_DIM" "$C_RESET"
  fi
  say

  printf '  source: %s\n' "$source_bin"
  printf '  target: %s\n' "$install_path"
  printf '  shell:  %s\n' "$shell_name"
  say

  if (( dry_run )); then
    printf '  %s~%s would create or update symlink %s%s%s -> %s%s%s\n' \
      "$C_YELLOW" "$C_RESET" "$C_CYAN" "$install_path" "$C_RESET" "$C_CYAN" "$source_bin" "$C_RESET"
  else
    mkdir -p "$bin_dir"
    ln -sf "$source_bin" "$install_path"
    ok "Installed symlink: $install_path -> $source_bin"
  fi

  if path_contains_dir "$bin_dir"; then
    ok "Bin dir already on PATH: $bin_dir"
  else
    warn "Bin dir is not currently on PATH: $bin_dir"
    say
    printf '%sAdd this to %s:%s\n' "$C_BOLD" "$rc_file" "$C_RESET"
    printf '  %s\n' "$path_snippet"
    say
    printf '%sThen reload your shell:%s\n' "$C_BOLD" "$C_RESET"
    case "$shell_name" in
      zsh) printf '  source %s\n' "$rc_file" ;;
      bash) printf '  source %s\n' "$rc_file" ;;
      fish) printf '  source %s\n' "$rc_file" ;;
    esac
  fi
  say
}

