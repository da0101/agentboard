#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# hub-route.sh — user-level Claude Code / Codex hook for repos that belong to a hub.
#
#   hub-route.sh session   SessionStart: inside a registered sibling repo, print the hub's
#                          start packet and the "shared repo" rule (stdout reaches the model).
#   hub-route.sh guard     PreToolUse: refuse edits to agent entry files (CLAUDE.md, AGENTS.md,
#                          GEMINI.md, .claude/ ...) inside a registered sibling repo (exit 2).
#
# Registry: $AB_HUBS_FILE (default ~/.agentboard/hubs.tsv), lines "<repo root>\t<hub>\t<repo id>",
# written by `ab hub register`. Self-contained and bash 3.2: it runs on every tool call, so it
# exits at the first line that says "not a registered repo". A GUARDRAIL, not a sandbox: it
# fails open on input it cannot parse. The user can lift it with AB_ALLOW_ENTRY_EDIT=1.
# -----------------------------------------------------------------------------
set -u

HUBS_FILE="${AB_HUBS_FILE:-$HOME/.agentboard/hubs.tsv}"
[[ -s "$HUBS_FILE" ]] || exit 0
MODE="${1:-}"
INPUT="$(cat 2>/dev/null || true)"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# jget <key> — first string value of "key" in the hook's JSON, unescaped
jget() {
  printf '%s' "$INPUT" | sed -En 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | awk 'NR == 1' \
    | awk '{ gsub(/\\n/, "\n"); gsub(/\\t/, "\t"); gsub(/\\"/, "\""); gsub(/\\\//, "/"); gsub(/\\\\/, "\\"); print }'
}

# norm <path> [base] — absolute, symlink-resolved when the directory exists
norm() {
  local p="$1" base="${2:-}" d f
  case "$p" in "~"/*) p="$HOME/${p#\~/}" ;; /*) ;; *) [[ -n "$base" ]] && p="$base/$p" ;; esac
  d="$(dirname "$p")"; f="$(basename "$p")"
  if [[ -d "$d" ]]; then d="$(cd "$d" 2>/dev/null && pwd -P)" || d="$(dirname "$p")"; fi
  [[ "$f" == "/" ]] && f=""
  printf '%s/%s' "${d%/}" "$f"
}

# repo_of <abs path> -> "root<TAB>hub<TAB>id" of the registered repo containing it (not a hub itself)
repo_of() {
  local lp; lp="$(lower "$1")"
  awk -F'\t' -v p="$lp" '
    { r = tolower($1); if (p == r || index(p, r "/") == 1) { if (length(r) > best) { best = length(r); line = $0 } } }
    END { if (line != "") print line }' "$HUBS_FILE"
}

CWD="$(jget cwd)"; [[ -n "$CWD" ]] || CWD="$(pwd -P)"
CWD="$(norm "$CWD/." "")"; CWD="${CWD%/.}"

case "$MODE" in
session)
  HIT="$(repo_of "$CWD")"; [[ -n "$HIT" ]] || exit 0
  IFS=$'\t' read -r ROOT HUB RID <<< "$HIT"
  printf '[Agentboard hub] This repo (%s) is part of the platform hub at %s.\n' "${RID:-$(basename "$ROOT")}" "$HUB"
  printf 'It is shared with developers who do not use Agentboard:\n'
  printf '  - NEVER create or edit CLAUDE.md, AGENTS.md, GEMINI.md or anything under .claude/ in this repo (a hook blocks it).\n'
  printf '  - Project knowledge belongs in the hub: cd %s && ab recall <topic>; record new facts there, not here.\n\n' "$HUB"
  if [[ -d "$HUB/.platform" ]] && command -v ab >/dev/null 2>&1; then
    (cd "$HUB" && NO_COLOR=1 ab brief --start 2>/dev/null) | awk 'NR <= 60'
  fi
  exit 0 ;;
guard)
  [[ "${AB_ALLOW_ENTRY_EDIT:-}" == "1" ]] && exit 0
  TOOL="$(jget tool_name)"
  TARGETS=""
  case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit) TARGETS="$(jget file_path)"; [[ -n "$TARGETS" ]] || TARGETS="$(jget notebook_path)" ;;
    apply_patch|*patch*)
      TARGETS="$(jget command | sed -En 's/^\*\*\* (Update|Add|Delete) File:[[:space:]]*//p; s/^\*\*\* Move to:[[:space:]]*//p')" ;;
    Bash|shell|local_shell|exec_command)
      CMD="$(jget command)"; [[ -n "$CMD" ]] || CMD="$(jget cmd)"
      [[ "$CMD" == *"*** Begin Patch"* ]] && TARGETS="$(printf '%s\n' "$CMD" | sed -En 's/^\*\*\* (Update|Add|Delete) File:[[:space:]]*//p; s/^\*\*\* Move to:[[:space:]]*//p')" || true
      # shell: a write-ish verb or redirect aimed at a protected name
      NAMES='(CLAUDE|AGENTS|GEMINI)(\.local|\.override)?\.md|\.claude(/|[[:space:]]|$)|\.codex(/|[[:space:]]|$)|\.gemini(/|[[:space:]]|$)'
      if printf '%s' "$CMD" | grep -Eq "(>>?|\btee( -a)?|\bsed -i[^|;&]*|\bperl -[a-z]*i[^|;&]*|\brm( -[a-zA-Z]+)*|\bmv|\btruncate[^|;&]*|\bcp [^|;&]*)[[:space:]]*[^|;&]*($NAMES)"; then
        HIT="$(repo_of "$CWD")"
        [[ -n "$HIT" ]] || { for r in $(awk -F'\t' '{print $1}' "$HUBS_FILE"); do [[ "$CMD" == *"$r"* ]] && HIT="$(grep -F "$r" "$HUBS_FILE" | awk 'NR==1')"; done; }
        if [[ -n "$HIT" ]]; then TARGETS="$TARGETS"$'\n'"(shell command touching an entry file)"; BLOCK_SHELL=1; fi
      fi ;;
    *) exit 0 ;;
  esac
  [[ -n "${TARGETS//[[:space:]]/}" ]] || exit 0
  while IFS= read -r T; do
    [[ -n "$T" ]] || continue
    if [[ "${BLOCK_SHELL:-}" == "1" && "$T" == "(shell command"* ]]; then
      IFS=$'\t' read -r ROOT HUB RID <<< "$HIT"; WHAT="$T"
    else
      A="$(norm "$T" "$CWD")"; HIT="$(repo_of "$A")"; [[ -n "$HIT" ]] || continue
      IFS=$'\t' read -r ROOT HUB RID <<< "$HIT"
      REL="${A:$(( ${#ROOT} + 1 ))}"     # by length: the registry and the path may differ in case
      B="$(basename "$A")"
      case "$B" in CLAUDE.md|AGENTS.md|GEMINI.md|CLAUDE.local.md|AGENTS.override.md) ;; *)
        case "$REL" in .claude|.claude/*|.codex|.codex/*|.gemini|.gemini/*) ;; *) continue ;; esac ;; esac
      WHAT="$REL"
    fi
    {
      printf 'Blocked by Agentboard: %s is a shared agent-entry file in the repo "%s", owned by developers who do not use Agentboard.\n' "$WHAT" "${RID:-$(basename "$ROOT")}"
      printf 'Do not change it. Put project knowledge in the hub instead (%s), or ask the user to make the change.\n' "$HUB"
      printf '(The user can lift this by launching the agent with AB_ALLOW_ENTRY_EDIT=1.)\n'
    } >&2
    exit 2
  done <<< "$TARGETS"
  exit 0 ;;
*) printf 'usage: hub-route.sh session|guard  (reads the hook JSON on stdin)\n' >&2; exit 0 ;;
esac
