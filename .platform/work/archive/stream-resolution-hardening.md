---
stream_id: stream-stream-resolution-hardening
slug: stream-resolution-hardening
type: bug
status: done
agent_owner: codex
domain_slugs: [platform-hardening]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/stream-resolution-hardening
created_at: 2026-04-18
updated_at: 2026-04-18
closure_approved: true
---

# stream-resolution-hardening

## Scope
- Fix stream resolution so stale env vars, stale session bindings, and invalid `BRIEF.md` references do not poison current-stream inference.
- Fix `new-stream` registration so `ACTIVE.md` remains a valid Markdown table as multiple streams are added.
- Refresh `BRIEF.md` automatically when it is placeholder or points at a missing stream file.
- Keep the fix scoped to stream bookkeeping and attribution; do not fold in unrelated daemon-orchestration or audit work.

## Done criteria
- [x] `resolve_current_stream` falls through stale `AGENTBOARD_STREAM` values instead of failing resolution
- [x] `agentboard log-reason` and other stream-resolution callers no longer tag closed or missing streams by default
- [x] `agentboard new-stream` preserves a valid `ACTIVE.md` table when multiple streams exist
- [x] `agentboard new-stream` rewrites `BRIEF.md` when the brief references a missing stream file
- [x] `bash tests/unit/log_reason_test.sh` passes
- [x] `bash tests/unit/commands_streams_test.sh` passes
- [x] Manual verification on this repo shows `BRIEF.md` and `ACTIVE.md` point only at active streams
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
2026-04-18 — Canonical stream resolution should degrade gracefully on stale state rather than treating missing streams as fatal — stale session/env state is normal after closures and should fall through to real active context.

## Resume state
- **Last updated:** 2026-04-18 — by codex
- **What just happened:** Finished the stream-resolution fixes, re-verified the focused command suites, and reconciled BRIEF/ACTIVE state in this repo.
- **Current focus:** Awaiting user review of the hardening results and closure decision.
- **Next action:** User decides whether to close the stream or request another pass.
- **Blockers:** none

## Progress log
2026-04-18 22:00 — Registered the stream to track BRIEF/current-stream bookkeeping fixes under the existing platform-hardening domain.
2026-04-18 22:33 — Verified `bash tests/unit/commands_streams_test.sh` and `bash tests/unit/log_reason_test.sh` after landing the bookkeeping fixes; BRIEF and ACTIVE now point only at active streams in this repo.

## Open questions
_none_

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
