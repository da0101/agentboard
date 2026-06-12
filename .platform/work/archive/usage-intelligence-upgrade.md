---
stream_id: stream-usage-intelligence-upgrade
slug: usage-intelligence-upgrade
type: feature
status: done
agent_owner: codex
domain_slugs: [usage-intelligence]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/usage-intelligence-upgrade
created_at: 2026-04-17
updated_at: 2026-04-18
closure_approved: true
---

# usage-intelligence-upgrade

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Improve usage logging so token spend is attributable by meaningful task type, not only broad complexity labels.
- Upgrade checkpoint-driven usage logging so long sessions can be broken into explainable segments.
- Improve `usage learn` / `optimize` so it can call out conversational drift, model overkill, and other token waste patterns earlier.
- Surface enough usage signal in the CLI that the user can answer “where did my Claude limit go?” without opening SQLite manually.
- Out of scope: external analytics services, per-message telemetry, or provider API integration.

## Done criteria
- [ ] `checkpoint` supports meaningful task-type attribution for auto-logged usage rows.
- [ ] `usage summary` / `usage optimize` / `usage learn` make conversational or model-selection waste visible when data supports it.
- [ ] Tests cover the new attribution and learning behavior.
- [ ] `bash tests/unit.sh` passes.
- [ ] `bash tests/integration.sh` passes.
- [ ] Manual verification shows the current usage data can explain the `watch-install` Claude Opus spend more clearly than before.
- [ ] `.platform/memory/log.md` appended
- [ ] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

## Resume state
_Overwritten by `agentboard checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-04-17 by danilulmashev
- **What just happened:** Fixed the last usage-intelligence bug in the savings path: usage learn --apply now writes learnings correctly, and the token-optimization rules for semantic task types and stage-boundary checkpointing are persisted in memory. Full unit suite still passes.
- **Current focus:** lib/agentboard/commands/usage.sh
- **Next action:** Update/install this agentboard build in the other projects, then use checkpoint with --type and more frequent stage-boundary logs so new sessions stop producing opaque normal/heavy blobs.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-04-17 HH:MM — <what happened>`._

2026-04-17 11:18 — Fixed the last usage-intelligence bug in the savings path: usage learn --apply now writes learnings correctly, and the token-optimization rules for semantic task types and stage-boundary checkpointing are persisted in memory. Full unit suite still passes.

2026-04-17 11:01 — Finished the usage-intelligence implementation: checkpoint now logs semantic task types separately from complexity, usage read paths tolerate legacy/read-only schemas, and brief/summary/optimize/learn surface coarse logging and generic-label blind spots. Added regression tests for inferred types, complexity, legacy DB reads, and brief warnings; unit and integration suites pass.

2026-04-17 10:37 — Created dedicated domain and stream for the usage-intelligence upgrade.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
