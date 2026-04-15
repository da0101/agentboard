# Subagent dispatch conventions

**Scope:** These rules apply when running in **Claude Code**. Codex CLI and Gemini CLI manage their own model selection — skip this file if you are not Claude Code.

---

## Rule 1 — Announce every dispatch

Before every `Task` tool call, print a manifest block in chat:

> **⚡ Dispatching N agent(s)**
>
> | Agent | Model | Task |
> |---|---|---|
> | **Max the Mapper** | 🔵 `sonnet` | map widget dataflow |
> | **Kai the Coder** | 🟣 `opus` | rewrite data layer |

Model emoji: 🔵 `sonnet` · 🟣 `opus` · 🟡 `haiku`

This renders as a visually distinct blockquote table in Claude Code's chat — never plain text. Never dispatch silently. The announcement lets the user see how many agents were spawned and which model each is burning.

---

## Rule 2 — Pick the right model

Pass `model` explicitly on every `Task` call. Never omit it — omitting it inherits the parent model (Opus) and wastes tokens.

| Work type | Model | Use for |
|---|---|---|
| Research, audit, exploration, doc writing, codebase mapping, code review, test writing, plan verification, security audit, UX review | **`sonnet`** | Read-only analysis and documentation |
| Code implementation (writing/editing production code), hard architectural decisions, executors that need to handle deviations mid-task | **`opus`** | Actual code writing |
| Mechanical, narrow, fast operations (file listing, simple greps, trivial summaries) | **`haiku`** | Genuinely trivial + latency matters |

**Default bias: Sonnet.** Opus is only for actual code writing and hard architectural calls.

---

## Rule 3 — Name agents with a persona

Agents must have a name + role format. Examples:

> Leo the Researcher, Max the Mapper, Kai the Coder, Rita the Test-Writer, Ada the Architect, Oli the Auditor, Sam the Scout, Finn the Fixer

The project owner picks a naming scheme during activation (role-based, themed, etc.). Once chosen, stick to it. The main agent proposes a scheme and the user confirms.

Personas make parallel dispatch logs readable and encourage thoughtful role assignment.

---

## Summary checklist (before every Task dispatch)

1. Print the manifest **block** (blockquote table — not a one-liner)
2. Include name + emoji model + purpose for each agent
3. Ensure `model` is passed explicitly in the Task call
4. 🔵 Sonnet for read-only; 🟣 Opus for code writing; 🟡 Haiku only for trivial ops
