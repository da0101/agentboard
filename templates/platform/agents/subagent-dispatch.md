# Subagent dispatch conventions

Rules for all three providers. Each section is scoped — read only yours.

---

## Claude Code

### Rule 1 — Announce every dispatch

Before every `Task` tool call, print a manifest block in chat:

> **⚡ Dispatching N agent(s)**
>
> | Agent | Model | Task |
> |---|---|---|
> | **Max the Mapper** | 🔵 `sonnet` | map widget dataflow |
> | **Kai the Coder** | 🟣 `opus` | rewrite data layer |

Model emoji: 🔵 `sonnet` · 🟣 `opus` · 🟡 `haiku`

This renders as a visually distinct blockquote table in Claude Code's chat. Never dispatch silently.

### Rule 2 — Pick the right model

Pass `model` explicitly on every `Task` call. Never omit it — omitting inherits the parent model (Opus) and wastes tokens.

| Work type | Model |
|---|---|
| Research, audit, exploration, doc writing, mapping, code review, test writing, plan verification | **`sonnet`** |
| Code implementation, hard architectural decisions, executors that handle deviations | **`opus`** |
| File listing, simple greps, trivial summaries | **`haiku`** |

**Default bias: Sonnet.** Opus only for actual code writing and hard architectural calls.

### Rule 3 — Name agents with a persona

> Leo the Researcher, Max the Mapper, Kai the Coder, Rita the Test-Writer, Ada the Architect, Oli the Auditor, Sam the Scout, Finn the Fixer

The project owner picks a naming scheme during activation. Once chosen, stick to it.

### Checklist (before every Task dispatch)

1. Print the manifest **block** (blockquote table — not a one-liner)
2. Include name + emoji model + purpose for each agent
3. Pass `model` explicitly in every Task call
4. 🔵 Sonnet for read-only; 🟣 Opus for code writing; 🟡 Haiku only for trivial ops

---

## Codex CLI

Codex uses named agents defined in `.codex/config.toml` + `.codex/agents/<name>.toml`.
Dispatch is via `spawn_agent` / `wait_agent`. Model is set per agent in the TOML.

### Rule 1 — Announce every dispatch

Before calling `spawn_agent`, print a text manifest in chat:

```
⚡ Dispatching N agent(s)
  researcher  codex-4-5 / medium  [task description]
  coder       codex-4-5 / high    [task description]
  auditor     codex-4-5 / high    [task description]
```

Never dispatch silently. One line per agent: name · model · task.

### Rule 2 — Pick the right agent

| Work type | Agent | Model | Effort |
|---|---|---|---|
| Research, exploration, mapping, doc writing, code review | `researcher` or `auditor` | `codex-4-5` | `medium` |
| Code implementation, architectural decisions | `coder` | `codex-4-5` | `high` |
| Security audit, verification | `auditor` | `codex-4-5` | `high` |
| File listing, greps, trivial summaries | `mapper` | `codex-4-5` | `low` |

**Default bias: researcher.** `coder` (o3) only when files must be written.

### Rule 3 — Use project-defined agent names

During activation the LLM replaces the generic roles (researcher/coder/auditor/mapper)
with project-specific ones matching the stack (e.g. flutter-agent, firebase-agent).
Use the names defined in `.codex/config.toml` — never invent new ones at dispatch time.

### Rule 4 — Log tokens per agent

Each spawned agent logs its own segment at session end:
```bash
agentboard usage log --provider codex --model <model> --stream <slug> \
  --type <type> --input <N> --output <N> --note "<agent-name>: <what it did>"
```

### Checklist (before every spawn_agent call)

1. Print the text manifest (one line per agent)
2. Use only agent names from `.codex/config.toml`
3. Confirm agent has correct `sandbox_mode` for the task (read-only vs full)
4. Each agent logs its own tokens at session end

---

## Gemini CLI

Gemini manages its own model selection and does not use the `.codex/` config.
Follow the same announce-before-dispatch rule but use plain text format (same as Codex above).
Model selection is Gemini-native — consult Gemini's own docs for model IDs.
