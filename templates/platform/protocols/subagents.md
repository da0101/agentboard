# Protocol: Subagent model assignment (Claude Code)

> Before every `Task` / `agent()` dispatch.

Before every `Task` tool dispatch, print a manifest block in chat:

> **⚡ Dispatching N agent(s)**
>
> | Agent | Model | Task |
> |---|---|---|
> | **Name** | 🔵 `sonnet` | purpose |

Model emoji: 🟤 `fable` · 🟣 `opus` · 🔵 `sonnet` · 🟡 `haiku`. Pass `model` explicitly on every `Task` or `agent()` call — never omit it (omitting inherits the caller's model and multiplies cost by agent count).

| Work type | Model |
|---|---|
| Frontier reasoning — greenfield architecture, hardest design decisions | 🟤 **`fable`** |
| Complex implementation, hard architectural decisions, deviation handling | 🟣 **`opus`** |
| Research, audit, exploration, doc writing, code review, test writing, security audit | 🔵 **`sonnet`** |
| Mechanical / trivial narrow operations | 🟡 **`haiku`** |

**Workflow agents (`/workflows`):** same rules apply per `agent()` call inside the script — research stages → `sonnet`, implementation stages → `opus`, trivial transforms → `haiku`. Never omit `model` in a workflow — it turns a 10-agent fan-out into a 10× token multiplier.

Name agents with a persona — e.g., "Max the Mapper", "Kai the Coder". Full rule: `.platform/agents/subagent-dispatch.md`.
