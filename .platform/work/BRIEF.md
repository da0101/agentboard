# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** silicon-valley-mindset
**Status:** awaiting-verification
**Stream file:** `.platform/work/silicon-valley-mindset.md`

---

## What we're building

We are adding a durable Agentboard mindset rule so PM and engineering agents approach product work like leading Silicon Valley product teams: ambitious, future-facing, user-obsessed, craft-driven, and execution-minded.

## Why

The owner wants every agent to raise the bar beyond basic task completion: think ahead, build for standout product quality, and push toward innovative, best-in-class outcomes without losing execution discipline.

## What done looks like

- The rule appears in shipped process/role templates read by future Claude, Codex, and Gemini sessions.
- PM and engineering roles frame work through user value, product differentiation, craft, and future leverage.
- The rule includes guardrails against vague hype or unapproved scope creep.
- Tests or contract checks cover the shipped wording if appropriate.

## Architecture decisions locked

- Ambition must be paired with disciplined scope, tests, and approval gates.
- "Silicon Valley mindset" means best-in-class product thinking and execution, not adding unapproved features.

## Current state

Implementation is complete in `/private/tmp/agentboard-silicon-valley-mindset` on `feature/silicon-valley-mindset`. Focused contract tests pass; the full unit suite has unrelated daemon startup failures in `daemon_test.sh`, `lock_test.sh`, and `log_reason_test.sh`.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load files relevant to the next task. Do not auto-load archived streams.

**Primary stream:** `.platform/work/silicon-valley-mindset.md`
**Domain:** `.platform/domains/product-engineering-mindset.md`
**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `.platform/work/ACTIVE.md`
- `.platform/work/silicon-valley-mindset.md`
- `.platform/domains/product-engineering-mindset.md`
- `templates/platform/workflow.md`
- `templates/platform/roles/`
- `templates/root/AGENTS.md.template`
- `templates/root/CLAUDE.md.template`
- `templates/root/GEMINI.md.template`
- `.platform/memory/log.md`
