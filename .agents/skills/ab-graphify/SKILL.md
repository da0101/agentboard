# ab-graphify

Graphify maps your entire codebase into a queryable structural knowledge graph stored at
`.platform/graphify/`. Use this skill to build or refresh the graph, and to reference it
during research.

**Mode: AST-only (no API key, no LLM, free).** This produces a structural graph — what
calls what, import chains, god nodes, import cycles — without any semantic extraction.
This is the right mode for AI agent use. Agents query the graph directly; no human-facing
report is needed.

## What it produces

After running, `.platform/graphify/graph.json` contains:
- All nodes (files, functions, classes) and edges (calls, imports, references)
- God nodes — most-connected abstractions in the codebase
- Community clusters — groups of files that belong together
- Import cycles — circular dependencies

## When to suggest running graphify

1. **After `ab init`** — if the init prompt was skipped or graphify was installed later.
2. **After `ab rescan`** — when ≥5 files changed, the graph may be stale.
3. **Before starting a new stream** that touches unfamiliar parts of the repo.

## How to invoke

No API key needed. Works in Claude Code, Codex CLI, Gemini CLI, and any other AI agent:

```bash
graphify update . --force --no-cluster
mkdir -p .platform/graphify
cp -R graphify-out/. .platform/graphify/
rm -rf graphify-out
```

## How to use the output

During `ab-research`, query `.platform/graphify/graph.json` to find structural connections:

```bash
# Find shortest path between two components
graphify path "ComponentA" "ComponentB" --graph .platform/graphify/graph.json

# Explain a node and its neighbors
graphify explain "function_name" --graph .platform/graphify/graph.json
```

Or ask the AI agent: "look at graph.json and tell me what calls X" — the agent can
read and reason over graph.json directly.

## Not installed?

```bash
uv tool install graphifyy && graphify install
```

Then re-run the commands above.
