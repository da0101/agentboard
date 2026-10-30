# -----------------------------------------------------------------------------
# ab graph build [--ref <ref>] [repo-id...]  |  ab graph list
#
# Builds code graphs with `graphify` (AST only, no API key) WITHOUT writing into any
# repo that is not yours to change:
#   single project   graphify update .   (output graphify-out/ — keep it git-ignored)
#   hub              one graph per sibling repo -> .platform/graphify/<repo>/graphify-out/graph.json
#                    plus a merged .platform/graphify/all-repos.json (every node tagged with its repo)
# A hub repo is exported to a scratch dir first (graphify cannot write elsewhere): from <ref>
# (default: .platform/recall-ref or env AB_RECALL_REF, e.g. origin/develop) with git archive, else
# its working tree minus ignored files. Sibling repos are only read. The scratch copy is deleted
# afterwards; `.platform/graphify/` gets a `*` .gitignore (graphs are big and regenerable).
# Query:  graphify query "<question>" --graph .platform/graphify/all-repos.json   (or one repo's graph.json)
# Pure bash 3.2; needs `graphify` on PATH (uv tool install graphifyy).
# -----------------------------------------------------------------------------

_graph_export() { # <repo> <ref> <dest> — copy the files graphify should read
  local r="$1" ref="$2" dest="$3"
  mkdir -p "$dest"
  if [[ -n "$ref" ]] && git -C "$r" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
    git -C "$r" archive "$ref" | tar -xf - -C "$dest"; printf '%s@%s' "$ref" "$(git -C "$r" rev-parse --short "$ref")"
  else
    git -C "$r" ls-files -co --exclude-standard | (cd "$r" && tar -cf - -T -) | tar -xf - -C "$dest"
    printf 'working tree@%s' "$(git -C "$r" rev-parse --short HEAD 2>/dev/null || echo none)"
  fi
}

cmd_graph_list() {
  local g="./.platform/graphify" d
  [[ -d "$g" ]] || { say "No hub graphs yet. Run: ab graph build"; return 0; }
  for d in "$g"/*/; do
    [[ -f "${d}graphify-out/graph.json" ]] || continue
    printf '  %-22s %6s  %s\n' "$(basename "$d")" "$(du -h "${d}graphify-out/graph.json" | cut -f1)" "$(cat "${d}SOURCE" 2>/dev/null)"
  done
  [[ -f "$g/all-repos.json" ]] && printf '  %-22s %6s  merged, nodes tagged by repo\n' "all-repos.json" "$(du -h "$g/all-repos.json" | cut -f1)"
  return 0
}

cmd_graph_build() {
  local ref="" want="" r rid name out src work hub n=0 graphs=""
  while [[ $# -gt 0 ]]; do
    case "$1" in --ref) [[ -n "${2:-}" ]] || die "--ref needs a value"; ref="$2"; shift 2 ;; --*) die "Unknown flag for graph build: $1" ;; *) want="$want $1"; shift ;; esac
  done
  command -v graphify >/dev/null 2>&1 || die "graphify not found. Install: uv tool install graphifyy"
  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."
  [[ -n "$ref" ]] || ref="$(_recall_ref)"
  hub="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  work="${AB_GRAPH_WORK:-$HOME/.agentboard/graph-src}"
  if [[ "$(_recall_roots | grep -c .)" -le 1 ]]; then
    say "Single project: graphify update ."
    graphify update . --force 2>&1 | grep -a "Rebuilt\|Error" | sed 's/^/  /'
    git check-ignore -q graphify-out 2>/dev/null || warn "graphify-out/ is not git-ignored — add it to .gitignore."
    return 0
  fi
  mkdir -p ./.platform/graphify; printf '*\n!.gitignore\n' > ./.platform/graphify/.gitignore
  while IFS=$'\t' read -r r rid; do
    [[ "$r" == "$hub" ]] && continue
    name="$(basename "$r")"
    if [[ -n "$want" ]]; then case " $want " in *" $name "*|*" $rid "*) ;; *) continue ;; esac; fi
    git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || { warn "$name is not a git repo — skipped"; continue; }
    out="./.platform/graphify/$name"; src="$work/$name"
    rm -rf "$src"; printf '  %s: ' "$name"
    mkdir -p "$out/graphify-out"
    printf '%s\n' "$(_graph_export "$r" "$ref" "$src")" > "$out/SOURCE"
    ( cd "$src" && graphify update . --force 2>&1 | grep -a "Rebuilt" | sed 's/.*Rebuilt: //' )
    if [[ -f "$src/graphify-out/graph.json" ]]; then cp "$src/graphify-out/graph.json" "$out/graphify-out/graph.json"; n=$((n + 1)); else warn "no graph produced for $name"; fi
    rm -rf "$src"
  done < <(_recall_roots)
  for r in ./.platform/graphify/*/graphify-out/graph.json; do [[ -f "$r" ]] && graphs="$graphs $r"; done
  if (( n > 0 )) && [[ "$(printf '%s\n' $graphs | grep -c .)" -gt 1 ]]; then
    # shellcheck disable=SC2086
    ( cd ./.platform/graphify && graphify merge-graphs */graphify-out/graph.json --out all-repos.json 2>&1 | tail -2 | sed 's/^/  /' )
  fi
  ok "Graphs in .platform/graphify/ (not committed). Query: graphify query \"<question>\" --graph .platform/graphify/all-repos.json"
}

cmd_graph() {
  case "${1:-}" in
    build) shift; cmd_graph_build "$@" ;;
    list)  shift; cmd_graph_list "$@" ;;
    -h|--help|"") sed -n 2,16p "$AGENTBOARD_ROOT/lib/agentboard/commands/graph.sh" | sed 's/^# \{0,1\}//' ;;
    *) die "Unknown graph subcommand: $1 (build, list)" ;;
  esac
}
