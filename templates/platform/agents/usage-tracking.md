# Global Usage Tracking Protocol

> **Audience:** Claude Code, Codex CLI, Gemini CLI.
> **Goal:** Accumulate token data across every context clear and provider switch so the user can make smart cost optimizations over time.

---

## Mental model

**One log entry = one context segment.**

A "context segment" is one uninterrupted context window with one provider. Every time you clear context, switch providers, or close a stream — that is a segment boundary. Log it.

Multiple segments can share the same `stream_slug`. The CLI aggregates them.

```
stripe-live-readiness  [claude / segment 1]  →  45 000 tokens
stripe-live-readiness  [claude / segment 2]  →  38 000 tokens  (after context clear)
stripe-live-readiness  [codex  / segment 3]  →  12 000 tokens  (provider switch)
stripe-live-readiness  [gemini / segment 4]  →  21 000 tokens  (another provider)
                                                ─────────────
                              stream total   →  116 000 tokens
```

---

## When to log — hard rules

Log a segment whenever ANY of these happen:

1. **You are about to clear your context window** — log before the clear.
2. **The user switches to a different AI provider** — log your segment before handing off.
3. **A stream is closed** (Stage 6 of the workflow) — log the final segment.
4. **The user says "log token usage"** — log immediately.

Never wait until stream closure if context clears happened in between — that data is lost.

---

## How to log

Run via Bash tool:

```bash
agentboard usage log \
  --provider claude \
  --model claude-sonnet-4-6 \
  --stream <stream-slug> \
  --type <task-type> \
  --input <input-token-estimate> \
  --output <output-token-estimate> \
  --note "segment 2 of 3 — implemented webhook handler"
```

**`--provider`** — `claude` | `codex` | `gemini`
**`--model`** — e.g. `claude-sonnet-4-6`, `gpt-4o`, `gemini-2.5-pro`
**`--stream`** — slug from the active `work/<slug>.md` (e.g. `stripe-live-readiness`)
**`--type`** — `research` | `implementation` | `debug` | `audit` | `hardening` | `chore`
**`--input`** / `--output`** — token counts for this segment (estimate if exact count unavailable)
**`--note`** — short description of what this segment covered (optional but recommended)

**Repo is auto-detected from the current directory.**

---

## Token estimation when exact counts are unavailable

Most CLI providers do not expose exact token counts to the agent. Use these estimates:

| Situation | Input estimate | Output estimate |
|---|---|---|
| Light session (few reads, short answers) | 10 000–25 000 | 2 000–5 000 |
| Medium session (several file reads, some code) | 25 000–60 000 | 5 000–15 000 |
| Heavy session (many files, long implementation) | 60 000–120 000 | 15 000–40 000 |
| Context window nearly full | 150 000–200 000 | 20 000–50 000 |

When in doubt, lean toward overestimating input. Output is usually 10–30% of input.

---

## Schema reference

```sql
CREATE TABLE usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    agent_provider TEXT NOT NULL,   -- 'claude', 'gemini', 'codex'
    model TEXT,                     -- e.g. 'claude-sonnet-4-6'
    stream_slug TEXT,               -- matches work/<slug>.md filename
    repo TEXT,                      -- auto-detected from cwd
    task_type TEXT,                 -- research / implementation / debug / audit / chore
    input_tokens INTEGER,
    output_tokens INTEGER,
    total_tokens INTEGER,
    estimated_cost REAL,            -- USD (optional, leave blank)
    note TEXT,                      -- e.g. "segment 2 — context clear after auth work"
    session_id TEXT                 -- optional grouping key
);
```

---

## Useful queries you can run

Check accumulated totals for the current stream:
```bash
agentboard usage stream <stream-slug>
```

Global summary (by provider, model, repo, task type):
```bash
agentboard usage summary
```

Optimization insights (most expensive task types and streams):
```bash
agentboard usage optimize
```

Cross-project query directly via SQLite:
```bash
sqlite3 ~/.agentboard/usage.db "
  SELECT stream_slug, SUM(total_tokens) AS total, COUNT(*) AS segments
  FROM usage GROUP BY stream_slug ORDER BY total DESC LIMIT 10;"
```

---

## Optimization protocol (before starting a medium+ task)

Before beginning any task estimated at Medium scope or larger:

1. Run `agentboard usage optimize` to check historical averages for this task type.
2. If similar tasks averaged >80 000 tokens, propose a more surgical approach:
   - Read specific line ranges instead of full files.
   - Load only the domain files listed in `work/BRIEF.md § Relevant context`.
   - Prefer `grep`/`glob` over reading whole directories.
3. Report the efficiency comparison at stream closure: "This stream used X tokens. Global average for `<type>` tasks: Y tokens."
