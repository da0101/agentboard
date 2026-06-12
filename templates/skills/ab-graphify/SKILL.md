# ab-graphify

Graphify maps your entire codebase into a queryable knowledge graph stored at
`.platform/graphify/`. Use this skill to build or refresh the graph, and to
reference it during research.

## What it produces

After running, `.platform/graphify/` contains:
- `graph.html` — interactive browser visualization (click nodes, filter, search)
- `GRAPH_REPORT.md` — key concepts, cross-cutting patterns, surprising connections, suggested questions
- `graph.json` — the full graph; query it any time without re-reading source files

## When to suggest running graphify

1. **After `ab init`** — if the init prompt was skipped or graphify was installed later.
2. **After `ab rescan`** — when ≥5 files changed, the graph may be stale.
3. **Before starting a new stream** that touches unfamiliar parts of the repo.

## How to invoke

Run via your shell tool (works in Claude Code, Codex, Gemini CLI, and any other AI agent):

```bash
graphify .
```

If graphify outputs to `graphify-out/` (its default), move the output:

```bash
mkdir -p .platform/graphify
cp -R graphify-out/. .platform/graphify/
rm -rf graphify-out
```

## How to use the output

During `ab-research`, read `.platform/graphify/GRAPH_REPORT.md` **first** — it surfaces
cross-cutting patterns and surprising connections that grep misses. Use `graph.json`
for precise dependency queries.

## Not installed?

If `graphify` is not found, tell the user:

```bash
uv tool install graphifyy && graphify install
```

Then re-run `graphify .` from the project root.
