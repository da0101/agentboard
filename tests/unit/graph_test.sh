#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# A fake graphify: `update` writes graphify-out/graph.json listing the files it was run over;
# `merge-graphs` concatenates its inputs. No real graphify needed.
setup_graph_fixture() {
  GF="$(mktemp -d)"; GF="$(cd "$GF" && pwd -P)"
  HUB="$GF/hub"; API="$GF/ApiServer"; WEB="$GF/web"
  mkdir -p "$HUB" "$API/src" "$WEB" "$GF/bin"
  printf 'x\n' > "$API/src/old.py"; printf 'x\n' > "$WEB/app.ts"
  make_git_repo "$API" main; commit_all "$API" initial
  make_git_repo "$WEB" main; commit_all "$WEB" initial
  git -C "$API" checkout -q -b dev; printf 'x\n' > "$API/src/only_on_dev.py"; commit_all "$API" "dev work"
  git -C "$API" checkout -q main
  printf '{}\n' > "$HUB/package.json"; make_git_repo "$HUB" main; commit_all "$HUB" initial
  init_project_fixture "$HUB"
  cat > "$HUB/.platform/repos.md" <<'EOT'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
| web-app | ../web | React | web.md |
EOT
  cat > "$GF/bin/graphify" <<'EOT'
#!/usr/bin/env bash
case "$1" in
  update) mkdir -p graphify-out; { printf '{"files":"'; find . -type f -not -path './graphify-out/*' | sort | tr '\n' ' '; printf '"}\n'; } > graphify-out/graph.json
          echo "[graphify watch] Rebuilt: 3 nodes, 2 edges, 1 communities" ;;
  merge-graphs) shift; out=""; files=(); while [[ $# -gt 0 ]]; do if [[ "$1" == --out ]]; then out="$2"; shift 2; else files+=("$1"); shift; fi; done
                cat "${files[@]}" > "$out"; echo "Merged ${#files[@]} graphs" ;;
esac
EOT
  chmod +x "$GF/bin/graphify"
  export PATH="$GF/bin:$PATH" AB_GRAPH_WORK="$GF/work"
}

test_build_makes_one_graph_per_repo_plus_a_merged_one() {
  local out
  setup_graph_fixture
  run_cli_capture out "$HUB" graph build
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$HUB/.platform/graphify/ApiServer/graphify-out/graph.json" "src/old.py"
  assert_file_contains "$HUB/.platform/graphify/web/graphify-out/graph.json" "app.ts"
  [[ -s "$HUB/.platform/graphify/all-repos.json" ]] || fail "merged graph missing"
  assert_file_contains "$HUB/.platform/graphify/.gitignore" "*"
  run_cli_capture out "$HUB" graph list
  assert_contains "$out" "ApiServer"; assert_contains "$out" "all-repos.json"
}

test_build_never_writes_into_a_sibling_repo_and_removes_its_scratch_copy() {
  setup_graph_fixture
  git -C "$API" status --porcelain --ignored > "$GF/before.txt"
  run_cli_capture OUT "$HUB" graph build
  git -C "$API" status --porcelain --ignored > "$GF/after.txt"
  cmp -s "$GF/before.txt" "$GF/after.txt" || fail "sibling repo changed"
  [[ ! -e "$API/graphify-out" && ! -e "$WEB/graphify-out" ]] || fail "graphify-out leaked into a sibling"
  [[ ! -e "$GF/work/ApiServer" ]] || fail "scratch copy left behind"
}

test_build_reads_the_ref_not_the_checked_out_branch() {
  setup_graph_fixture
  run_cli_capture OUT "$HUB" graph build --ref dev
  assert_file_contains "$HUB/.platform/graphify/ApiServer/graphify-out/graph.json" "only_on_dev.py"
  assert_file_contains "$HUB/.platform/graphify/ApiServer/SOURCE" "dev@"
  printf 'dev\n' > "$HUB/.platform/recall-ref"          # the same ref via the hub's recall-ref file
  run_cli_capture OUT "$HUB" graph build api-server
  assert_file_contains "$HUB/.platform/graphify/ApiServer/graphify-out/graph.json" "only_on_dev.py"
  assert_file_contains "$HUB/.platform/graphify/web/SOURCE" "working tree"   # no such ref there: falls back
}

test_build_without_graphify_says_how_to_install_it() {
  local out
  setup_graph_fixture
  rm -f "$GF/bin/graphify"
  PATH="/usr/bin:/bin" run_cli_capture out "$HUB" graph build
  assert_contains "$out" "graphify not found"
}

test_build_makes_one_graph_per_repo_plus_a_merged_one
test_build_never_writes_into_a_sibling_repo_and_removes_its_scratch_copy
test_build_reads_the_ref_not_the_checked_out_branch
test_build_without_graphify_says_how_to_install_it
