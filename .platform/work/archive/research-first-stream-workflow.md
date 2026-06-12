---
stream_id: stream-research-first-stream-workflow
slug: research-first-stream-workflow
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [new-stream-workflow, templates]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/research-first-stream-workflow
created_at: 2026-04-27
updated_at: 2026-04-27
closure_approved: false
---

# research-first-stream-workflow

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Define a strict new-stream intake workflow shared by Codex, Claude, and Gemini.
- Require precise research before implementation for non-trivial new streams, including problem context, similar approaches, current patterns, implementation techniques, and best practices.
- Require detailed planning after research: development phases, risk mitigation, complexity assessment, alternatives, and clarifying questions.
- Require implementation to follow the researched plan with explicit human validation, review, and approval gates.
- Out of scope: building a new UI, changing git commit policy, or removing existing stream bootstrap requirements.

## Done criteria
- [x] Canonical workflow docs describe the research-first new-stream structure.
- [x] Shipped provider entry templates point all LLM providers to the same new-stream intake rules.
- [x] Relevant skills/templates reinforce the research, planning, human-in-loop, implementation, and verification gates.
- [x] Regression checks cover the changed workflow/template text where practical.
- [x] Manual verification confirms the instructions are coherent from a fresh-agent point of view.
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `2026-04-27 — <decision> — <rationale>`_

- 2026-04-27 — Every new stream requires scaled research, targeted external research, and human approval before implementation — small streams can keep research compact, but skipping research is no longer allowed once work becomes a stream.

## Resume state
_Overwritten by `agentboard checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-04-27 by danilulmashev
- **What just happened:** Implemented research-first new-stream workflow across canonical docs, provider entries, skills, tests, and memory.
- **Current focus:** —
- **Next action:** Review wording with the user; if approved, run closure protocol after setting closure_approved true.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-04-27 HH:MM — <what happened>`._

2026-04-27 11:38 — Implemented research-first new-stream workflow across canonical docs, provider entries, skills, tests, and memory.

2026-04-27 11:12 — Registered stream/domain and completed initial local + external research for a research-first new-stream workflow.

## Open questions
_Things blocked on user input. Remove when resolved._

_Resolved 2026-04-27: research is mandatory for every new stream, scaled by risk, with targeted external research included._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
