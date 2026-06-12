#!/usr/bin/env bash
# Optional graphify detection and prompt — called from cmd_init.
# Detects graphify on PATH, prompts y/N if found, prints install tip if not.
# Never fails: all code paths return 0 so ab init always completes.

_graphify_maybe_prompt() {
  local target="${1:-.}"

  if ! command -v graphify >/dev/null 2>&1; then
    say
    dim "  Tip: install graphify to map this codebase into a queryable knowledge graph."
    dim "       uv tool install graphifyy && graphify install"
    return 0
  fi

  say
  if ! ask_yes_no "Graphify detected — build a knowledge graph now?"; then
    return 0
  fi

  say
  printf '  Running graphify…\n'
  local dest_dir="$target/.platform/graphify"

  graphify . 2>&1 | sed 's/^/  /'
  local graphify_exit="${PIPESTATUS[0]}"

  if (( graphify_exit == 0 )); then
    mkdir -p "$dest_dir"
    if [[ -d "graphify-out" ]]; then
      cp -R "graphify-out/." "$dest_dir/"
      rm -rf "graphify-out"
    fi
    ok "Knowledge graph → ${C_CYAN}.platform/graphify/${C_RESET}"
    dim "  Open graph.html in a browser, or ask the LLM about GRAPH_REPORT.md."
  else
    printf '  %sWarning: graphify exited with an error — skipped.%s\n' "$C_YELLOW" "$C_RESET"
  fi
  say
}
