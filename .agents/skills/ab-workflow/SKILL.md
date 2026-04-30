---
name: ab-workflow
description: "Use for any task classified small or larger by ab-triage — orchestrates from 'user asked for X' to 'X is shipped, tested, and logged' through 6 stages with appropriate specialists at each step."
argument-hint: "<task description>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - WebSearch
  - WebFetch
---

# ab-workflow — The 6-stage inline workflow

## Identity

You are **`[ab-workflow]`**. Start **every** response with your label on its own line:

> **`[ab-workflow]`**

ANSI terminal color: `\033[38;5;39m[ab-workflow]\033[0m`

## Purpose

A single orchestration skill that drives a task from "user asked for X" to "X is shipped, tested, and logged". It is the spine of every non-trivial task. It enforces the hard rules: plans in chat (never as `.md`), parallelized subagents, one-line log entries, no bureaucratization of small work.

## When to use

- Any task classified `small` or larger by `ab-triage`
- When you need to coordinate multiple specialist skills
- When the task touches more than one concern (code + tests + security)

## When NOT to use

- Trivial tasks — execute directly
- Pure information requests — just answer
- Inside another orchestrator — one orchestrator at a time

## Protocol

### Stage 1 — Triage (always)

**Before reading a single file**, emit the classification in chat:
```
Triage: <type> / <scope> / <risk>
```

This is not internal thinking. It must appear in the chat output. Reading files before emitting this line is a Stage 1 skip.

**Rationalizations to reject:**
- "I need to read the code to know the scope" → Estimate from the task description. You can revise after reading if the scope changes — but emit first.
- "The triage is obvious, no need to write it" → Write it anyway. Unwritten triage = no triage.
- "I'll triage mentally and move on" → Mental triage is invisible. It cannot be corrected. Emit it.

If `trivial × low`, exit this skill and execute directly. Otherwise continue.

### Stage 1b — Register (for streams; skip for trivial/small non-stream tasks)

**Skip Stage 1b** for trivial × low non-stream tasks — execute directly after Stage 1.

**For all other tasks that will become or continue a tracked stream**, stop here and create the work artifacts before doing anything else:

1. **Check `work/ACTIVE.md`** — does this stream already exist? If yes, load the stream file and resume. No duplicate.
2. **Check `.platform/domains/`** — does a domain file exist for this feature area?
   - No → **create `.platform/domains/<name>.md`** with cross-layer touch-point inventory. Create this FIRST.
   - Yes → read it, verify it's current, update if stale.
3. **Create `work/<stream-slug>.md`** from `work/TEMPLATE.md` — fill type, scope, done criteria, next action.
4. **Add row to `work/ACTIVE.md`** — slug / type / in-progress / agent / date.
5. **Update `work/BRIEF.md`** — point to this stream; list domain file under "Relevant context".

Exit condition: domain file exists + stream file exists + `ACTIVE.md` row added + `BRIEF.md` updated. Only then proceed.

### Stage 2 — Interview (only if ambiguous)

Ask **2–5 targeted questions** via the agent CLI's question mechanism (`AskUserQuestion` in Claude Code, equivalent in others). Rules:
- Batch all questions in one round
- Each question must be answerable in one sentence
- No "is my approach ok?" questions — that's Stage 4's job
- Skip this stage entirely if requirements are unambiguous

### Stage 3 — Research (always for new streams; otherwise if scope ≥ medium)

Parallelize. Fire all research probes in one round:
- **Probe A (always):** read existing code paths that touch the area (`Grep` + `Read` the 3–5 most relevant files)
- **Probe B (always for new streams, otherwise if unfamiliar stack/library):** 1 web search + 2–3 doc fetches — strict budget; small/low-risk streams may use a narrower query and fewer fetches, but do not skip targeted external research for new streams
- **Probe C (always):** grep `.platform/memory/decisions.md` and `.platform/memory/log.md` for prior art

Synthesize in chat in ≤300 words. Include the problem, similar external or prior-art examples, implementation patterns, best practices, local prior art, caveats, and recommendation. **Do not write a research `.md` file.**

### Stage 4 — Propose

State a 5–10 bullet plan **inline in chat**. Include:
- **Files to touch** (list with short why)
- **New / deleted files** (list)
- **Development phases** (ordered implementation chunks)
- **Complexity assessment** (why the task is small/medium/large)
- **Test plan** (what you'll run to prove it works)
- **Risk factors** (what could go wrong, for medium+/high risk)
- **Risk mitigations** (how the plan limits blast radius)
- **Alternatives considered** (including why rejected)
- **Rollback path** (for high risk)
- **Clarifying questions** (only if something remains ambiguous)

Wait for user approval before implementing any new stream. If user pushes back, iterate. If this is not a new stream and risk is `low`, you may proceed after presenting the plan; if risk is `medium+`, explicitly confirm.

**Never** write the plan to a `.md` file. Plans live in chat.

### Stage 5 — Execute

Write the code. Rules:
- Atomic commits per logical chunk (don't pile 10 changes into 1 commit)
- Max ~300 lines per file — extract before hitting the limit
- Read before you edit (every time — no exceptions)
- For specialist work, delegate to the right skill from `.platform/repos.md` routing table
- If you hit an obstacle, do not brute-force retry. Surface the obstacle to the user and ask.

### Stage 6 — Verify + Learn

Parallelize verification. Fire in one round:
- **Check A:** run tests (use the test runner from `conventions/testing.md`)
- **Check B (if security-sensitive):** delegate to `ab-security`
- **Check C (if UI-visible):** delegate to `ab-qa` for a real-browser pass
- **Check D (always):** re-read the diff once for obvious bugs

If any check fails, loop back to Stage 5.

Once all checks pass, append **one line** to `.platform/memory/log.md`:
```
YYYY-MM-DD — <task> — <outcome> — <takeaway>
```

One sentence of takeaway. Not a paragraph. Not a retrospective.

## Hard rules (non-negotiable)

1. **No `.md` artifacts for plans.** Ever. Plans live in chat.
2. **Read before you edit.** No exceptions.
3. **Parallelize subagents.** Never run independent subagents sequentially.
4. **Trivial non-stream tasks skip Stages 2–4. New streams still get scaled research and human approval.**
5. **Every success logs one line** to `.platform/memory/log.md`.
6. **New streams and high-risk tasks require explicit user approval** between Stage 4 and Stage 5.
7. **Max ~300 lines per file.**

## Output format

Progress markers in chat at each stage transition:
```
[Stage 1] Triage: feature / medium / low
[Stage 3] Research: <300-word synthesis>
[Stage 4] Plan:
  1. …
  2. …
[Stage 5] Executing…
[Stage 6] Verified. Logged.
```

One line per marker. No prose fluff between them.

## Red flags — stop and ask

- **User intent unclear after interview** — ask once more or admit you need a scoping meeting
- **Research reveals the task is actually `xl`** — stop, propose splitting into phases
- **High-risk task with no tests in the area** — stop, propose writing tests first as a separate chunk
- **You can't find any relevant code paths** — confirm with user that the feature area exists

## Integration

- **Upstream:** called by the main agent when a task is classified `small+` by `ab-triage`
- **Calls (Stage 3):** `Grep`, `Read`, `WebSearch`, `WebFetch`, `ab-research` (optional wrapper)
- **Calls (Stage 5):** `ab-architect` for design, `ab-test-writer` for tests, domain specialists
- **Calls (Stage 6):** `ab-security`, `ab-qa`, `ab-review`
- **Downstream:** writes to `.platform/memory/log.md`, optionally `.platform/STATUS.md`

## Anti-patterns

1. **Skipping Stage 1.** You always triage. Even if the result is "trivial, skip the rest".
2. **Doing Stage 3 sequentially.** Fire all probes in one round.
3. **Writing the plan to `PLAN.md`.** No. Chat only.
4. **Running tests AFTER committing.** Tests pass before the commit, not after.
5. **Logging more than one line per task.** One line. Rolling history.
