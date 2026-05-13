---
stream_id: stream-manual-qa-plan-workflow
slug: manual-qa-plan-workflow
type: feature
status: done
agent_owner: codex
domain_slugs: [new-stream-workflow]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/manual-qa-plan-workflow
created_at: 2026-05-13
updated_at: 2026-05-13
closure_approved: true
---

# manual-qa-plan-workflow

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Add a mandatory manual QA plan step to the Agentboard workflow when a task requires human click-through or behavior verification.
- Define a precise, structured, emoji-visible QA plan format that agents must provide at the end of implementation.
- Update live workflow docs, shipped templates, and relevant skills/provider instructions so future agents follow the rule.
- Add focused regression tests that lock the workflow contract.
- Out of scope: building a browser automation runner or replacing automated tests.

## Done criteria
- [x] Workflow requires a manual QA plan whenever a feature, bug fix, or debugging task needs human verification.
- [x] Manual QA plan format includes prerequisites, environment, steps, expected results, edge cases/regressions, and pass/fail notes.
- [x] Relevant live docs/templates/skills/provider entry points are updated consistently.
- [x] Focused tests cover the new workflow contract.
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-05-13 — Manual QA plan belongs in Stage 6 — It must be produced after implementation/verification when the agent knows the final behavior and tester needs exact click-through steps.

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-05-13 by danilulmashev
- **What just happened:** Audited stream, fixed live provider entry gap, and anchored all-green audit; manual QA workflow is ready for owner-approved closure.
- **Current focus:** —
- **Next action:** If owner approves closure, set closure_approved true and run the close protocol; otherwise keep awaiting verification.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-05-13 11:13 — Audited stream, fixed live provider entry gap, and anchored all-green audit; manual QA workflow is ready for owner-approved closure.

2026-05-13 11:07 — Implemented manual QA plan workflow: Stage 6, provider templates, workflow/QA skills, tests, decisions, and memory now require guided QA steps when human verification matters.

2026-05-13 10:25 — Registered stream, ran PM review and compact research: Stage 6 needs a required manual QA plan artifact when human behavior verification is relevant.

## Open questions
_Things blocked on user input. Remove when resolved._
