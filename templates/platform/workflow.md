# Workflow — The 6-Stage Inline Workflow

> **Audience:** any AI agent (Claude Code, Codex CLI, Gemini CLI) or human working on this project.
> **Goal:** move fast on small tasks, think carefully on big ones, and never bureaucratize small work.

---

## The 6 stages

```
Triage → Interview → Research → Propose → Execute → Verify + Learn
```

Each stage has a clear entry condition and a clear exit condition. Skip stages that don't apply.

### 1. Triage

For every non-trivial task, state inline in chat:

- **Type:** bug / feature / refactor / chore / investigation / docs
- **Scope:** trivial / small / medium / large
- **Risk:** low / medium / high (blast radius + reversibility)

**Exit:** you know how big this is and how careful to be.

Trivial tasks (typo fix, rename, 1-line config change) skip directly to Stage 5.

### 1b. Register (mandatory for non-trivial tasks)

**Before doing anything else** — research, proposals, code — register the workstream:

1. **Check `work/ACTIVE.md`** — does this stream already exist? If yes, load the stream file and continue from where it left off. Do not create a duplicate.
2. **Check `.platform/domains/`** — does a domain file exist for **this specific concern**?
   - Ask: "Does an existing domain file fully describe the cross-repo touch-points for THIS concern (which files in which repos, what the API contract is, what breaks if this changes)?" A related-but-different domain file does NOT count.
   - If **yes and it's accurate**: read it, verify it's current, update if stale.
   - If **no, or the existing file only partially covers it**: create `.platform/domains/<name>.md` with the cross-layer touch-point inventory. Create it NOW, before the stream file.
   - **Common trap:** finding a domain file for a nearby feature (e.g. `menu-builder.md`) and treating it as sufficient for a different concern (e.g. subdomain routing). These are separate concerns and require separate domain files.
3. **Create `work/<stream-slug>.md`** from `work/TEMPLATE.md` — fill in type, scope, done criteria, next action.
4. **Add a row to `work/ACTIVE.md`** — slug / type / in-progress / agent / date.
5. **Update `work/BRIEF.md`** — set primary stream to this task; add domain file under "Relevant context".

**Why this is non-negotiable:** if the context is cleared, the computer restarts, or a different agent picks up the work, the stream file is the only way to resume. Zero registration = zero traceability = zero resumability. A workstream without a domain file has no focused context for the next agent.

Full protocol: `conventions/work-tracking.md` § "Starting a new workstream".

**Exit:** domain file exists, stream file exists, `ACTIVE.md` has the row, `BRIEF.md` is current.

### 2. Interview

**Only if requirements are ambiguous.** Ask 2–5 targeted questions. Do not ask "is my plan ready?" — use the plan-approval tool for that.

**Exit:** requirements are unambiguous.

### 3. Research

**Only for medium+ scope.** Parallelize:
- Subagent A: read existing code paths that touch the area
- Subagent B: web search / docs fetch (strict budget: 1 search + 2–3 fetches)
- Subagent C: check conventions/ and decisions.md for prior art

Synthesize in chat (≤300 words). **Do not** write a research `.md` file.

**Exit:** you understand the area well enough to propose.

### 4. Propose

State a 5–10 bullet plan **inline in chat**. Include:
- Files to touch
- New files / deleted files
- Test plan
- Risk factors
- Rollback path (for risky changes)

**Do not** write a plan `.md` file. If the user approves, proceed. If they push back, iterate.

**Exit:** user has approved the plan (or you're in autonomous mode and the plan passes your own gate).

### 5. Execute

Write the code. Atomic commits per logical chunk. Max ~300 lines per file.

For specialist work, delegate to the appropriate skill from `repos.md`.

**Backlog rule:** When you encounter a real limitation, tech debt item, or missing feature that is out of scope for the current task — do NOT fix it, do NOT open a new work stream. Append one row to `.platform/BACKLOG.md` (priority / area / description / found-during / date) and continue. Priority guide: `high` = causes user-visible bugs or data loss at scale / `medium` = degrades UX or requires workaround / `low` = nice-to-have or edge case.

**Exit:** code is written, tests pass locally.

### 6. Verify + Learn

Parallelize:
- Specialist A: run tests
- Specialist B: security / code review pass (for anything security-sensitive)
- Specialist C: real-browser QA (for UI changes)

Then **learn in three layers:**

**Layer 1 — Log (always):** append one line to `.platform/log.md`:
```
YYYY-MM-DD — <task> — <outcome> — <takeaway>
```

**Layer 2 — Learnings (if bug was non-obvious):** if the root cause required >10 min to diagnose OR depended on internal behavior that isn't self-evident from the code, append an entry to `.platform/learnings.md` using the L-NNN format:
```
## L-NNN — <short title>
Date: YYYY-MM-DD | Repo: <repo>
Symptom: <what the developer/user sees>
Root cause: <the actual reason>
Fix: <what was changed and where>
Class: <category — for grep>
```

**Layer 3 — Memory (if architectural):** if the insight is a stable cross-session invariant (a new pattern, a recurring gotcha, an API contract), update `memory/MEMORY.md` or a topic file under `memory/`.

**Bug investigation rule:** before diagnosing any non-obvious bug, grep `.platform/learnings.md` for the symptom keyword first. Don't re-diagnose a known class of problem.

**Exit:** task is done, recorded, and learned from.

---

## Hard rules

1. **No `.md` artifacts for plans.** Plans live in chat. Only write `.md` files when they're genuinely reusable (specs, docs, conventions). **`work/` stream files are the exception — they are mandatory operational state, not plan documents. Always create them (Stage 1b) before starting non-trivial work.**
2. **Max ~300 lines per file.** Extract components before hitting the limit.
3. **Trivial tasks skip to Stage 5.** Don't bureaucratize small work.
4. **Parallelize subagents.** Never run independent subagents sequentially.
5. **Every success logs one line.** `.platform/log.md` is append-only, newest-on-top.
6. **Read before you edit.** Always read the file before modifying it, even if you "know" the content.
7. **Ask before destructive actions.** Deletes, force-pushes, rollbacks, schema drops — always confirm.

---

## Model profile hint (Claude Code, optional)

| Scope | Suggested profile |
|---|---|
| Trivial | Haiku / cheapest |
| Small | Sonnet / balanced |
| Medium | Sonnet / balanced |
| Large | Opus / quality |
| High-risk | Opus / quality |

---

## Integration with agent CLIs

- **Claude Code:** `CLAUDE.md` at project root auto-loads. Skills in `.claude/skills/` extend this workflow.
- **Codex CLI:** `AGENTS.md` at project root auto-loads. Same content as CLAUDE.md, regenerated by `scripts/sync-context.sh`.
- **Gemini CLI:** `GEMINI.md` at project root auto-loads. Same content as CLAUDE.md, regenerated by `scripts/sync-context.sh`.

All three read the same `.platform/` reference pack.
