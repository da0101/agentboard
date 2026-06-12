---
stream_id: stream-event-log-dedup
slug: event-log-dedup
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [orchestration]
repo_ids: [repo-primary]
base_branch: main
git_branch: fix/event-log-dedup
created_at: 2026-04-18
updated_at: 2026-04-18
closure_approved: false
---

# event-log-dedup

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Stop duplicate `FileChange` rows when multiple Codex/Gemini pollers watch the same dirty worktree.
- Preserve legitimate repeat logging when the same file changes again or returns clean and becomes dirty later.
- Keep the fix inside the non-Claude session tracker and its runtime metadata.
- Out of scope: changing Claude native hook behavior, redesigning stream resolution, or rewriting the daemon/event viewer.

## Done criteria
- [x] Concurrent non-Claude pollers share one dedup state, so the same dirty snapshot is emitted once.
- [x] A file is emitted again when its diff fingerprint changes or after it returns clean and becomes dirty again.
- [x] `bash tests/unit/session_track_test.sh`
- [x] `bash tests/unit/commands_doctor_test.sh`
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `2026-04-18 — <decision> — <rationale>`_

- 2026-04-18 — FileChange dedup is keyed by persisted per-file diff fingerprints, not per-process filename memory — concurrent wrappers and poller restarts need a shared view of what has already been emitted.

## Resume state
_Overwritten by `agentboard checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-04-18 23:11 — by codex
- **What just happened:** Reproduced the duplicate `FileChange` pattern as a poller-coordination bug, replaced filename-only in-memory dedup with shared persisted diff-state dedup, and added regressions for concurrent pollers and repeat edits.
- **Current focus:** Waiting for user verification that the fix behaves correctly in real multi-project use.
- **Next action:** Run the wrappers in another repo, confirm duplicate batches are gone, then either close the stream or capture any remaining edge case.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-04-18 HH:MM — <what happened>`._

- 2026-04-18 23:11 — Fixed duplicate `FileChange` emission by sharing diff-state across pollers, updated runtime gitignore coverage, and added tracker regressions for concurrent sessions and clean round-trips.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
