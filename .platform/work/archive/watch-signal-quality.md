---
stream_id: stream-watch-signal-quality
slug: watch-signal-quality
type: feature
status: done
agent_owner: codex
domain_slugs: [commands]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/watch-signal-quality
created_at: 2026-04-17
updated_at: 2026-04-18
closure_approved: true
---

# watch-signal-quality

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Make `agentboard watch` produce stream-progress checkpoints, not arbitrary repo-wide dirty-file snapshots.
- Prefer files that are likely relevant to the active stream when generating auto-checkpoint `--what` and `--focus`.
- Suppress repeated auto-checkpoints when the dirty-file set has not materially changed since the last watch write.
- Keep the existing "fresh manual checkpoint" skip behavior and the scheduler/foreground watch surfaces intact.
- Out of scope: semantic diff analysis, per-provider file filtering, or cross-repo stream inference.

## Done criteria
- [ ] Repeated watch ticks on the same unchanged dirty-file set do not keep rewriting identical auto-checkpoints.
- [ ] Auto-checkpoint summaries prefer stream-relevant files over generic scaffolding noise when both are dirty.
- [ ] Unit tests cover noisy `.claude/skills` style cases plus duplicate-snapshot suppression.
- [ ] `bash tests/unit.sh` passes.
- [ ] `bash tests/integration.sh` passes.
- [ ] Manual verification shows `watch --once` on a mixed dirty repo points to stream work instead of generic tooling files.
- [ ] `.platform/memory/log.md` appended
- [ ] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-04-17 — Rank changed files before checkpointing instead of trusting raw `git status` order — the current order is mechanical and over-exposes lexically early scaffolding paths like `.claude/skills/*`.
2026-04-17 — Suppress duplicate auto-watch snapshots based on the ranked focus set + change count — stream files should only move when the observed state materially changes.

## Resume state
_Overwritten by `agentboard checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-04-17 by danilulmashev
- **What just happened:** Hardened watch again after a real takecare-platform smoke test: if every changed file is still negative-signal tooling churn, auto-watch now skips the tick entirely. Verified by rerunning watch --once against takecare-platform/contact-tab-delete-fix; the old noisy 11:04 entry remained unchanged instead of appending another fake progress snapshot.
- **Current focus:** lib/agentboard/commands/watch.sh
- **Next action:** Decide whether to mark this stream awaiting verification or keep it open for broader heuristics; the immediate noise bug is fixed and smoke-tested.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-04-17 11:06 — Hardened watch again after a real takecare-platform smoke test: if every changed file is still negative-signal tooling churn, auto-watch now skips the tick entirely. Verified by rerunning watch --once against takecare-platform/contact-tab-delete-fix; the old noisy 11:04 entry remained unchanged instead of appending another fake progress snapshot.

2026-04-17 10:51 — Fixed watch signal quality: rank stream-relevant changed files, ignore untracked-only noise and self-written stream files, and suppress duplicate snapshots unless the ranked file state changes.

2026-04-17 11:07 — Created a dedicated stream to fix misleading watch checkpoints caused by repo-wide dirty state.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
