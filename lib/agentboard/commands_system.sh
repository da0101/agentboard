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

cmd_update() {
  local dry_run=0
  for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && dry_run=1
  done

  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  require_templates

  printf '\n%s%sagentboard update%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if (( dry_run )); then
    printf '%s  Dry-run mode — no files will be changed.%s\n' "$C_DIM" "$C_RESET"
  fi
  say

  local updated=0 added=0 skipped=0

  # -------------------------------------------------------------------------
  # PROCESS FILES — always replace with latest template version.
  # These contain only workflow/process instructions — zero project-specific
  # data. Safe to overwrite on every update.
  # -------------------------------------------------------------------------
  head "Process files (replace with latest)"

  local pf
  for pf in \
    "workflow.md" \
    "ONBOARDING.md" \
    "ACTIVATE.md" \
    "ACTIVATE-HUB.md" \
    "work/TEMPLATE.md" \
    "domains/TEMPLATE.md"; do
    local src="$TEMPLATES_PLATFORM/$pf"
    local dst="./.platform/$pf"
    [[ -f "$src" ]] || continue  # template doesn't have this file
    [[ -f "$dst" ]] || continue  # project doesn't have this file (e.g. hub-only)
    if (( dry_run )); then
      printf '  %s~%s %s\n' "$C_YELLOW" "$C_RESET" "$pf"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      printf '  %s↻%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$pf" "$C_RESET"
    fi
    updated=$((updated + 1))
  done

  # conventions/*.md — upsert: update existing AND add new ones
  if [[ -d "$TEMPLATES_PLATFORM/conventions" ]]; then
    local csrc
    for csrc in "$TEMPLATES_PLATFORM/conventions"/*.md; do
      [[ -f "$csrc" ]] || continue  # glob matched nothing (empty dir) — skip
      local cfname; cfname="$(basename "$csrc")"
      local cdst="./.platform/conventions/$cfname"
      local conv_is_new=0
      [[ -f "$cdst" ]] || conv_is_new=1
      if (( dry_run )); then
        if (( conv_is_new )); then
          printf '  %s+%s conventions/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$cfname" "$C_DIM" "$C_RESET"
        else
          printf '  %s~%s conventions/%s\n' "$C_YELLOW" "$C_RESET" "$cfname"
        fi
      else
        mkdir -p "./.platform/conventions"
        cp "$csrc" "$cdst"
        if (( conv_is_new )); then
          printf '  %s+%s %sconventions/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$cfname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sconventions/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$cfname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # agents/*.md — upsert: update existing AND add new ones (agentboard-global protocol files)
  if [[ -d "$TEMPLATES_PLATFORM/agents" ]]; then
    local asrc
    for asrc in "$TEMPLATES_PLATFORM/agents"/*.md; do
      [[ -f "$asrc" ]] || continue  # glob matched nothing (empty dir) — skip
      local afname; afname="$(basename "$asrc")"
      local adst="./.platform/agents/$afname"
      local agent_is_new=0
      [[ -f "$adst" ]] || agent_is_new=1
      if (( dry_run )); then
        if (( agent_is_new )); then
          printf '  %s+%s agents/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$afname" "$C_DIM" "$C_RESET"
        else
          printf '  %s~%s agents/%s\n' "$C_YELLOW" "$C_RESET" "$afname"
        fi
      else
        mkdir -p "./.platform/agents"
        cp "$asrc" "$adst"
        if (( agent_is_new )); then
          printf '  %s+%s %sagents/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$afname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sagents/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$afname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # skills — always replace (pure protocol content; project-specific work lives in .platform/)
  local skills_dir_claude="./.claude/skills"
  local skills_dir_agents="./.agents/skills"
  local skills_dir_codex="./.codex/skills"
  if [[ -d "$TEMPLATES_SKILLS" ]] && { [[ -d "$skills_dir_claude" ]] || [[ -d "$skills_dir_agents" ]] || [[ -d "$skills_dir_codex" ]]; }; then
    local sk_src sk_name sk_dst_c sk_dst_a sk_dst_x
    for sk_src in "$TEMPLATES_SKILLS"/*/; do
      sk_name="$(basename "$sk_src")"
      sk_dst_c="$skills_dir_claude/$sk_name"
      sk_dst_a="$skills_dir_agents/$sk_name"
      sk_dst_x="$skills_dir_codex/$sk_name"
      local skill_updated=0
      for sk_dst in "$sk_dst_c" "$sk_dst_a" "$sk_dst_x"; do
        [[ -d "$sk_dst" ]] || continue
        if (( dry_run )); then
          printf '  %s~%s skills/%s\n' "$C_YELLOW" "$C_RESET" "$sk_name"
        else
          cp -R "$sk_src/." "$sk_dst/"
          printf '  %s↻%s %sskills/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$sk_name" "$C_RESET"
        fi
        skill_updated=1
        updated=$((updated + 1))
      done
      # avoid double-counting when more than one skills dir exists
      if [[ $skill_updated -eq 1 ]]; then
        local skill_dir_count=0
        [[ -d "$sk_dst_c" ]] && skill_dir_count=$((skill_dir_count + 1))
        [[ -d "$sk_dst_a" ]] && skill_dir_count=$((skill_dir_count + 1))
        [[ -d "$sk_dst_x" ]] && skill_dir_count=$((skill_dir_count + 1))
        if (( skill_dir_count > 1 )); then
          updated=$((updated - (skill_dir_count - 1)))
        fi
      fi
    done
  fi

  # scripts/sync-context.sh
  local sc_src="$TEMPLATES_PLATFORM/scripts/sync-context.sh"
  local sc_dst="./.platform/scripts/sync-context.sh"
  local repos_file="./.platform/repos.md"
  if [[ -f "$sc_src" ]] && [[ -f "$sc_dst" ]]; then
    if (( dry_run )); then
      printf '  %s~%s scripts/sync-context.sh\n' "$C_YELLOW" "$C_RESET"
    else
      cp "$sc_src" "$sc_dst"
      chmod +x "$sc_dst"
      if [[ -f "$repos_file" ]]; then
        local sync_paths="" repo_row repo_id repo_path repo_stack repo_ref repo_abs repo_name current_repo
        current_repo="$(pwd)"
        while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
          [[ -n "$repo_abs" ]] || continue
          [[ "$repo_abs" == "$current_repo" ]] && continue
          sync_paths="${sync_paths}${repo_abs}"$'\n'
        done < <(concrete_repo_rows "$repos_file")
        if [[ -n "$sync_paths" ]]; then
          write_sync_repos_array "$sc_dst" "$sync_paths"
        fi
      fi
      printf '  %s↻%s %sscripts/sync-context.sh%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET"
    fi
    updated=$((updated + 1))
  fi

  # scripts/hooks/ — always upsert (no project-specific content; propagate bug fixes)
  if [[ -d "$TEMPLATES_PLATFORM/scripts/hooks" ]]; then
    local hook_src hook_dst hname
    for hook_src in "$TEMPLATES_PLATFORM/scripts/hooks"/*; do
      hname="$(basename "$hook_src")"
      hook_dst="./.platform/scripts/hooks/$hname"
      if (( dry_run )); then
        if [[ -f "$hook_dst" ]]; then
          printf '  %s~%s scripts/hooks/%s\n' "$C_YELLOW" "$C_RESET" "$hname"
        else
          printf '  %s+%s scripts/hooks/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$hname" "$C_DIM" "$C_RESET"
        fi
      else
        local hook_is_new=0
        [[ -f "$hook_dst" ]] || hook_is_new=1
        mkdir -p "./.platform/scripts/hooks"
        cp "$hook_src" "$hook_dst"
        chmod +x "$hook_dst"
        if (( hook_is_new )); then
          printf '  %s+%s %sscripts/hooks/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$hname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sscripts/hooks/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$hname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # -------------------------------------------------------------------------
  # ADD-IF-MISSING FILES — copy from template only if the project doesn't
  # have them yet. These may accumulate project-specific entries over time
  # (L-001, L-002, backlog items), so existing files are never overwritten.
  # -------------------------------------------------------------------------
  head "New files (add if missing)"

  local af
  for af in "learnings.md" "BACKLOG.md" "domains/TEMPLATE.md"; do
    local src="$TEMPLATES_PLATFORM/$af"
    local dst="./.platform/$af"
    [[ -f "$src" ]] || continue
    if [[ -f "$dst" ]]; then
      printf '  %s↷%s %s%s%s  %s(exists — kept as-is)%s\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$af" "$C_RESET" "$C_DIM" "$C_RESET"
      skipped=$((skipped + 1))
    else
      if (( dry_run )); then
        printf '  %s+%s %s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$af" "$C_DIM" "$C_RESET"
      else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        printf '  %s+%s %s%s%s  %s(new)%s\n' \
          "$C_GREEN" "$C_RESET" "$C_CYAN" "$af" "$C_RESET" "$C_DIM" "$C_RESET"
      fi
      added=$((added + 1))
    fi
  done

  # .claude/settings.json — add-if-missing (user may have custom hooks; don't clobber)
  local settings_src="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_dst="./.claude/settings.json"
  if [[ -f "$settings_src" ]]; then
    if [[ -f "$settings_dst" ]]; then
      printf '  %s↷%s %s.claude/settings.json%s  %s(exists — kept as-is)%s\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
      skipped=$((skipped + 1))
    else
      if (( dry_run )); then
        printf '  %s+%s .claude/settings.json  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$C_RESET"
      else
        mkdir -p "./.claude"
        cp "$settings_src" "$settings_dst"
        printf '  %s+%s %s.claude/settings.json%s  %s(new)%s\n' \
          "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
      fi
      added=$((added + 1))
    fi
  fi

  # -------------------------------------------------------------------------
  # Summary
  # -------------------------------------------------------------------------
  say
  if (( dry_run )); then
    printf '%s%s━━━ Dry-run complete ━━━%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
    printf '  Would update %s%d%s, add %s%d%s, keep %s%d%s\n' \
      "$C_BOLD" "$updated" "$C_RESET" \
      "$C_BOLD" "$added"   "$C_RESET" \
      "$C_BOLD" "$skipped" "$C_RESET"
    say
    printf '  %sRun without --dry-run to apply.%s\n' "$C_DIM" "$C_RESET"
  else
    printf '%s%s━━━ Update complete ━━━%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    printf '  %s↻%s updated: %s%d%s   %s+%s added: %s%d%s   %s↷%s kept: %s%d%s\n' \
      "$C_GREEN" "$C_RESET" "$C_BOLD" "$updated" "$C_RESET" \
      "$C_GREEN" "$C_RESET" "$C_BOLD" "$added"   "$C_RESET" \
      "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skipped" "$C_RESET"
    say
    printf '  %sNever touched:%s architecture.md, decisions.md, log.md, STATUS*.md,\n' "$C_DIM" "$C_RESET"
    printf '  %s              repos.md, work/ACTIVE.md, work/BRIEF.md, work/*.md, domains/*.md%s\n' "$C_DIM" "$C_RESET"
    printf '  %s              %s(except domains/TEMPLATE.md)%s\n' "$C_DIM" "$C_YELLOW" "$C_RESET"
  fi
  say
}

cmd_version() { say "agentboard $VERSION"; }

cmd_help() {
  cat <<'EOF'
agentboard — AI agent context kit

Bootstraps a .platform/ context pack into any project so that Claude Code,
Codex CLI, and Gemini CLI are instantly productive.

USAGE
  agentboard <command> [args]

COMMANDS
  install [--dir ...]        Install agentboard onto your PATH via a symlink
  init                       Scaffold a .platform/ pack in the current directory.
                             After init, open the project in an AI CLI and say
                             "activate this project" — the LLM scans your code
                             and fills in the context pack based on what it finds.

  update [--dry-run]         Update process files to the latest agentboard version.
                             Replaces: workflow.md, ONBOARDING.md, ACTIVATE.md,
                               conventions/*.md, domains/TEMPLATE.md,
                               scripts/sync-context.sh
                             Adds if missing: learnings.md, BACKLOG.md
                             Never touches: architecture.md, decisions.md, log.md,
                               STATUS*.md, repos.md, work/*, domains/*
                               except domains/TEMPLATE.md

  sync [--apply|--list]      Sync AGENTS.md + GEMINI.md from CLAUDE.md (default: check)
  bootstrap [--apply-domains] Discover repos, infer starter domains, and suggest streams
  migrate [--apply]          Upgrade legacy stream/domain files to metadata v1
  brief-upgrade [slug] ...   Rewrite legacy BRIEF.md for one target stream
  doctor                     Validate active .platform state and metadata
  new-domain <slug> ...      Create a domain file from the shared template
  new-stream <slug> ...      Create a stream file and register it in work/ACTIVE.md
  resolve <target>           Resolve a stream, domain, or repo by canonical id
  handoff [stream-slug]      Print a low-token provider handoff packet
  claim "<task>"             Add a row to .platform/sessions/ACTIVE.md
  release                    Remove your rows from .platform/sessions/ACTIVE.md
  log "<one line>"           Append a timestamped line to .platform/log.md
  status                     Print .platform/STATUS.md to stdout
  add-repo <path>            Copy per-repo entry file templates to a new repo
                             Refuses to overwrite existing entry files.
  version                    Print version
  help                       Show this help

ENV
  AGENTBOARD_AGENT           Agent name used in claim/release (default: $USER@$HOSTNAME)

PHILOSOPHY
  No stack pre-picking. No assumptions. The LLM decides what conventions to
  write based on your actual codebase during activation.
EOF
}

