# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** research-first-stream-workflow
**Status:** awaiting-verification
**Stream file:** `work/research-first-stream-workflow.md`

---

## What we're building

We are adding a strict research-first intake structure for new Agentboard streams. When Codex, Claude, Gemini, or another provider detects that a user request should become a new stream, the workflow should force precise research, detailed planning, human validation, and then implementation that follows the approved plan.

## Why

New streams are the moment where vague requirements, weak research, and premature implementation create the most downstream churn. The workflow should make discovery, planning, risk mitigation, alternatives, and human-in-the-loop approval explicit before code changes begin.

## What done looks like

- New stream detection rules are clear across provider entry files and workflow docs
- Research-first requirements cover the problem, comparable external approaches, current patterns, implementation techniques, and best practices
- Planning requirements cover phases, risks, complexity, alternatives, clarifying questions, and approval gates
- Implementation rules require following the researched plan with human validation, review, and approval

## Architecture decisions locked

- Canonical workflow rules live in `.platform/workflow.md` and the shipped template copy
- Provider entry templates should refer to one shared contract instead of drifting into provider-specific variants

## Current state

Implementation is complete and awaiting user verification. The contract is encoded in the live workflow docs, shipped workflow template, provider root templates, live/shipped skills, memory decision/log, and focused regression tests. Focused tests pass; the full unit suite still exposes the existing/flaky daemon startup timing issue in `daemon_test.sh`.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load the files listed here. Everything else is out of scope for this feature.
> Prefer `.platform/domains/<name>.md` files (cross-layer, focused) over repo-wide files.
> Repo files (`backend.md`, `admin.md`, etc.) are conventions — load only if you need to understand patterns.

- `.platform/domains/new-stream-workflow.md` — focused domain for this stream
- `.platform/domains/templates.md` — shipped template payload context
- `.platform/workflow.md` — current activated workflow contract
- `templates/platform/workflow.md` — shipped workflow contract
- `templates/root/CLAUDE.md.template` — Claude root-entry provider instructions
- `templates/root/AGENTS.md.template` — Codex root-entry provider instructions
- `templates/root/GEMINI.md.template` — Gemini root-entry provider instructions
- `templates/skills/ab-workflow/SKILL.md` — workflow orchestrator instructions
- `templates/skills/ab-research/SKILL.md` — research workflow instructions
- `templates/skills/ab-triage/SKILL.md` — classification gate instructions
- `.agents/skills/ab-workflow/SKILL.md` — live installed workflow skill
- `.agents/skills/ab-research/SKILL.md` — live installed research skill
- `.agents/skills/ab-triage/SKILL.md` — live installed triage skill
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` — live provider entry files for this repo
- `tests/unit/entry_templates_handoff_test.sh` — provider template invariant coverage
- `tests/unit/workflow_contract_test.sh` — workflow/skill invariant coverage

**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `.platform/workflow.md`
- `templates/platform/workflow.md`
- `templates/root/CLAUDE.md.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `templates/skills/ab-workflow/SKILL.md`
- `templates/skills/ab-research/SKILL.md`
- `templates/skills/ab-triage/SKILL.md`
- `.agents/skills/ab-workflow/SKILL.md`
- `.agents/skills/ab-research/SKILL.md`
- `.agents/skills/ab-triage/SKILL.md`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `tests/unit/entry_templates_handoff_test.sh`
- `tests/unit/workflow_contract_test.sh`
