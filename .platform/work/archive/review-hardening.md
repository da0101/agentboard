---
stream_id: stream-review-hardening
slug: review-hardening
type: feature
status: done
agent_owner: claude
domain_slugs: [platform-hardening, core, commands]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/review-hardening
created_at: 2026-06-11
updated_at: 2026-06-11
closure_approved: true
---

# review-hardening

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- _TODO: 3–5 bullets describing what's in scope_
- _TODO: be explicit about what's OUT of scope too_

## Done criteria
- [x] All 6 review findings fixed and released as v1.12.0 (PRs #21, #22; tag pushed; release workflow green)
- [x] tests/unit.sh (42 files, 338 tests) + tests/integration.sh (10 tests) pass on ubuntu + macOS CI and locally under bash 3.2
- [x] CLI smoke (version/help both bins), AT&T substitution repro fixed, all 8 PR checks green incl. first macOS runs
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated (size ratchet, loopback scan allowlist, patsub_replacement guard)

## Key decisions
_Append-only. Format: `2026-06-11 — <decision> — <rationale>`_

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| _TODO_ | _TODO_ | `feature/review-hardening` | `develop` | _TODO: installed / blocker_ | _TODO_ | _TODO_ |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-11 by danilulmashev
- **What just happened:** Released v1.12.0: PR #21 merged to develop, PR #22 (develop->main) merged, tag v1.12.0 pushed, release workflow green. All 8 CI checks pass incl. new macOS jobs. Fixed 2 latent bash-5.2 bugs surfaced by CI (patsub_replacement, errexit post-increment) and added user-approved loopback allowlist to security scans. Worktree removed.
- **Current focus:** —
- **Next action:** Stream done pending human closure approval (closure_approved flip is yours).
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-06-11 HH:MM — <what happened>`._

2026-06-11 20:50 — Released v1.12.0: PR #21 merged to develop, PR #22 (develop->main) merged, tag v1.12.0 pushed, release workflow green. All 8 CI checks pass incl. new macOS jobs. Fixed 2 latent bash-5.2 bugs surfaced by CI (patsub_replacement, errexit post-increment) and added user-approved loopback allowlist to security scans. Worktree removed.

2026-06-11 18:34 — All 6 review findings implemented and verified on feature/review-hardening (commit c504f2d in worktree): sed injection fix (3 instances), portable locking, macOS CI, 5 file splits + size ratchet, doc drift, test runner DX. 338 unit + 10 integration tests pass under bash 3.2.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_

## Dev environment
- Worktree: /Users/danilulmashev/Documents/GitHub/agentboard-wt-review-hardening (branch feature/review-hardening from main; develop is 50 commits stale)
- Dev command: bash tests/unit.sh && bash tests/integration.sh (pure bash, no deps to install, no localhost ports)
