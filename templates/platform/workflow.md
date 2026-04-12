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

Write the code. Max ~300 lines per file. For specialist work, delegate to the appropriate skill from `repos.md`.

> **⛔ Do NOT commit during Stage 5.** Code is written but never committed until Stage 6 passes and the user explicitly approves.

**When dispatching implementation sub-agents:** never include `git add` or `git commit` in the agent's task prompt. Agents write code and report back. The commit is the main agent's responsibility after Stage 6 clears and the human approves.

**After execution completes:** present a change summary inline — files modified/created, expected behavior change, what Stage 6 needs to verify.

**Backlog rule:** When you encounter a real limitation, tech debt item, or missing feature that is out of scope — do NOT fix it, do NOT open a new work stream. Append one row to `.platform/BACKLOG.md` (priority / area / description / found-during / date) and continue.

**Exit:** code is written, NOT yet committed, ready for Stage 6 verification.

### 6. Verify + Gate + Learn

#### The commit gate — required before ANY `git commit`

All three must be true before committing:

| Gate | Requirement |
|---|---|
| ✅ Tests pass | Unit tests for every new/modified function and component |
| ✅ Security clear | Quick pass on anything touching auth, payments, or data access |
| ✅ Human approves | User explicitly says "ship it" / "commit it" — the AI never self-approves |

Present Stage 6 results to the user **before committing**. Wait for the green light.

Then verify in parallel:
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

## Stream Closure Protocol

> **Hard rule: only the human/owner declares a stream complete.**
> The AI never self-declares completion. The AI may say "I believe this stream is done — here is the evidence" and propose closure, but the final decision belongs to the developer. No exceptions.
>
> **⛔ Do NOT run steps 7–9 (archive, ACTIVE.md removal, log) until the human explicitly approves closure.** Implementation being done ≠ stream being closed. The stream file stays in `work/` and the row stays in `ACTIVE.md` until the owner says so. Steps 1–6 (verify criteria, update docs) can run after implementation. Steps 7–9 require explicit human sign-off.

Run this checklist **every time a stream reaches done** — before archiving the stream file.

> **Why:** skipping this leaves stale docs for the next session/agent. Completed features must be fully reflected in all reference files before the stream is archived.

1. **Verify done criteria** — open the stream file (`work/<slug>.md`), confirm every checkbox is ticked.
2. **Update STATUS files** — for every repo the stream touched, mark features ✓ Done, update Last touched date, remove from Immediate priorities.
3. **Update domain file** — open `.platform/domains/<name>.md` if one exists. Update file paths, API shapes, cross-repo touch-points that changed.
4. **Deep-reference file check** — for every repo the stream touched, make an explicit YES/NO decision on whether the per-repo reference file (e.g. `backend.md`, `admin.md`) is now stale. Ask: *"Would a new developer or agent reading this file today take a wrong path?"* Update if YES. Skip if NO. This catches: new URL routes, removed fields, stack changes, patterns that no longer apply. State the decision in chat either way.
5. **Update architecture.md** — if the stream changed system topology (new endpoints, new data flows, auth changes), update the relevant section.
6. **Unblock downstream streams** — flip any `pending (blocked on this)` stream in `ACTIVE.md` to `ready-to-plan`.
7. **Archive the stream file** — first check: does the stream file have `closure_approved: true`? If not, **STOP**. Do not archive. Ask the owner to set it. Only when `closure_approved: true` is present: move `work/<slug>.md` → `work/archive/<slug>.md`, remove from `ACTIVE.md`, reset `BRIEF.md`. **Remove the closed stream from `BRIEF.md` entirely — do NOT add a "Previously completed" section.** Completed work belongs in `log.md` only. `BRIEF.md` must only ever list active streams.
8. **Append to log.md** — one line: `YYYY-MM-DD — <stream> — <outcome> — <takeaway>`.
9. **Learnings check** — any non-obvious bugs surfaced? Confirm they are in `learnings.md`. Add if missing.

**Hard rule:** steps 2–5 are not optional. If a stream touched 3 repos, all 3 STATUS files get updated and all 3 deep-reference files get an explicit YES/NO decision. The next agent should be able to open any reference file and see a correct picture of the world.

---

## Hard rules

1. **No `.md` artifacts for plans.** Plans live in chat. Only write `.md` files when they're genuinely reusable (specs, docs, conventions). **`work/` stream files are the exception — they are mandatory operational state, not plan documents. Always create them (Stage 1b) before starting non-trivial work.**
2. **Max ~300 lines per file.** Extract components before hitting the limit.
3. **Trivial tasks skip to Stage 5.** Don't bureaucratize small work.
4. **Parallelize subagents.** Never run independent subagents sequentially.
5. **Every success logs one line.** `.platform/log.md` is append-only, newest-on-top.
6. **Read before you edit.** Always read the file before modifying it, even if you "know" the content.
7. **Ask before destructive actions.** Deletes, force-pushes, rollbacks, schema drops — always confirm.
8. **Never commit before Stage 6 + human approval.** Execute produces code. Stage 6 + the human produces the commit. No exceptions — not even for "trivial" changes.
9. **Never include `git commit` in sub-agent prompts.** Agents write code and stop. If an agent is told to commit, it bypasses tests and human approval — exactly the failure mode this rule prevents.

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
