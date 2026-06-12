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

## Backend requirement — read before running

Graphify needs a direct API key to do semantic extraction. It **cannot** use Claude Code
or Codex CLI authentication — those authenticate via subscription/OAuth, not raw keys.
Always pass `--backend` explicitly to avoid burning quota on the wrong provider.

**Check which key is available:**
```bash
env | grep -E '^(ANTHROPIC|OPENAI|GEMINI|DEEPSEEK)_API_KEY' | sed 's/=.*/=set/'
```

**Pick the matching backend:**

| Key set | Command |
|---|---|
| `ANTHROPIC_API_KEY` | `graphify . --backend claude` |
| `OPENAI_API_KEY` | `graphify . --backend openai` |
| `GEMINI_API_KEY` (paid tier) | `graphify . --backend gemini` |
| None / free tier only | `graphify . --backend ollama` (requires `ollama` + a local model) |

**No API key at all?** Tell the user they need one of: an Anthropic API key
(`console.anthropic.com`), an OpenAI API key, or a paid Gemini key. Claude Code /
Codex CLI subscriptions do not expose keys that graphify can use.

## How to invoke

```bash
graphify . --backend <claude|openai|gemini|ollama>
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
