#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cmd_synthesize — show knowledge synthesis status for this project.
# Reports what has accumulated (archives, QA docs, memory files) and the
# state of .platform/knowledge/. The actual AI synthesis is done by the
# /ab-synthesize Claude Code skill.
# -----------------------------------------------------------------------------

cmd_synthesize() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local show_help=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) show_help=1; shift ;;
      *) die "Unknown flag: $1. Run 'ab synthesize --help'." ;;
    esac
  done

  if (( show_help )); then
    _synthesize_help; return 0
  fi

  local archive_dir="./.platform/work/archive"
  local qa_dir="./.platform/work/qa"
  local memory_dir="./.platform/memory"
  local knowledge_dir="./.platform/knowledge"

  # Count sources
  local n_archives=0 n_qa=0
  [[ -d "$archive_dir" ]] && n_archives=$(find "$archive_dir" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  [[ -d "$qa_dir"      ]] && n_qa=$(find "$qa_dir" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

  # Count memory files
  local -a mem_files=()
  for f in decisions learnings gotchas playbook BACKLOG open-questions; do
    [[ -f "${memory_dir}/${f}.md" ]] && mem_files+=("$f")
  done

  # Count knowledge docs
  local n_knowledge_md=0 n_knowledge_jsonl=0
  if [[ -d "$knowledge_dir" ]]; then
    n_knowledge_md=$(find "$knowledge_dir" -maxdepth 1 -name "*.md" ! -name "index.md" 2>/dev/null | wc -l | tr -d ' ')
    n_knowledge_jsonl=$(find "$knowledge_dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  fi

  # Last synthesis timestamp
  local last_synthesis="never"
  local index_file="${knowledge_dir}/index.md"
  if [[ -f "$index_file" ]]; then
    local ts
    ts="$(grep "^synthesized_at:" "$index_file" 2>/dev/null | head -1 | sed 's/^synthesized_at:[[:space:]]*//')"
    [[ -n "$ts" ]] && last_synthesis="$ts"
  fi

  # Compute rough accumulation since last synthesis
  local new_archives=0
  if [[ "$last_synthesis" != "never" && -d "$archive_dir" ]]; then
    new_archives=$(find "$archive_dir" -maxdepth 1 -name "*.md" -newer "$index_file" 2>/dev/null | wc -l | tr -d ' ')
  else
    new_archives="$n_archives"
  fi

  say ""
  say "${C_BOLD}Knowledge Synthesis — $(basename "$(pwd)")${C_RESET}"
  say "────────────────────────────────────────────"
  say ""
  say "  ${C_BOLD}Sources${C_RESET}"
  say "    Archived streams  :  ${C_YELLOW}${n_archives}${C_RESET} file(s)"
  say "    QA docs           :  ${C_YELLOW}${n_qa}${C_RESET} file(s)"
  if [[ ${#mem_files[@]} -gt 0 ]]; then
    say "    Memory files      :  ${C_YELLOW}${#mem_files[@]}${C_RESET} (${mem_files[*]})"
  else
    say "    Memory files      :  ${C_DIM}none found${C_RESET}"
  fi
  say ""
  say "  ${C_BOLD}Knowledge docs${C_RESET}"
  if [[ "$last_synthesis" == "never" ]]; then
    say "    Last synthesis    :  ${C_RED}never run${C_RESET}"
    say "    Synthesized docs  :  0"
  else
    say "    Last synthesis    :  ${C_GREEN}${last_synthesis}${C_RESET}"
    say "    Synthesized docs  :  ${n_knowledge_md} .md  +  ${n_knowledge_jsonl} .jsonl"
    if (( new_archives > 0 )); then
      say "    New since last    :  ${C_YELLOW}${new_archives} archive(s) not yet synthesized${C_RESET}"
    else
      say "    New since last    :  ${C_GREEN}up to date${C_RESET}"
    fi
  fi
  say ""

  if (( n_archives == 0 && n_qa == 0 && ${#mem_files[@]} == 0 )); then
    warn "Nothing to synthesize — no archive/, qa/, or memory/ content found."
    return 0
  fi

  say "  Run ${C_BOLD}/ab-synthesize${C_RESET} in Claude Code to generate/update knowledge docs."
  say ""
}

_synthesize_help() {
  cat <<'EOF'
Usage: ab synthesize

Shows the knowledge synthesis status for this project:
  - How many archived streams, QA docs, and memory files exist
  - When .platform/knowledge/ was last synthesized
  - How many new archives have accumulated since the last synthesis

The actual AI synthesis is performed by the /ab-synthesize Claude Code skill.
Run that skill to generate or update .platform/knowledge/*.md files.

Knowledge domains synthesized:
  features.md         Capability inventory
  architecture.md     Design decisions and patterns
  infrastructure.md   Services, deployment, config
  security.md         Security posture and known issues
  optimization.md     Performance work and bottlenecks
  technical-debt.md   Prioritized debt items
  limitations.md      Known limits and workarounds
  backlog.md          Curated backlog

EOF
}
