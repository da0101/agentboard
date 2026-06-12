---
stream_id: stream-sync-command-fallback
slug: sync-command-fallback
type: bug
status: done
agent_owner: codex
domain_slugs: [commands]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/sync-command-fallback
created_at: 2026-05-13
updated_at: 2026-05-13
closure_approved: true
---

# sync-command-fallback

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Fix `ab sync` when a repo does not have an executable project-local `.platform/scripts/sync-context.sh`.
- Keep `ab sync` behavior unchanged for initialized Agentboard projects.
- Improve the error path so users see public commands (`ab init`, `ab update`) rather than an internal script path.
- Add focused regression coverage for the missing-script case.
- Out of scope: redesigning multi-repo sync semantics or changing the `sync-context.sh` file format.

## Done criteria
- [x] `ab sync` still delegates to project-local `sync-context.sh` when present.
- [x] `ab sync` gives an actionable message when `.platform/` exists but the sync script is missing or not executable.
- [x] `ab update` restores missing `.platform/scripts/sync-context.sh` for older projects.
- [x] `ab update` preserves executable permissions after multi-repo `REPOS=()` rewrites.
- [x] `bash tests/unit/commands_sync_test.sh` passes.
- [x] `bash tests/unit/commands_update_test.sh` passes.
- [x] Manual QA plan included for trying the fix in `takecare-platform`.
- [x] `takecare-platform` source entry file updated and synced so `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` carry the same current workflow rules.
- [x] `.platform/memory/log.md` appended
- [x] No durable `decisions.md` update required; project-local sync decision recorded in this stream.

## Key decisions
_Append-only. Format: `2026-05-13 — <decision> — <rationale>`_

- 2026-05-13 — Keep `ab sync` project-local — `sync-context.sh` stores per-project repo lists and derives the repo root from its installed location, so falling back to Agentboard's template copy would sync the wrong repository.

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-05-13 by danilulmashev
- **What just happened:** Updated takecare-platform CLAUDE.md with provider-neutral current workflow rules, synced AGENTS/GEMINI, and verified all listed repos are in sync.
- **Current focus:** —
- **Next action:** User reviews diffs; if approved, close stream and commit Agentboard fix. Commit TakeCare repo changes separately by repo.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-05-13 HH:MM — <what happened>`._

2026-05-13 11:55 — Updated takecare-platform CLAUDE.md with provider-neutral current workflow rules, synced AGENTS/GEMINI, and verified all listed repos are in sync.

2026-05-13 11:46 — Takecare verification found the multi-repo REPOS rewrite dropped executable mode; fixed chmod ordering and shared writer, tests pass, and takecare sync --apply now succeeds.

2026-05-13 11:36 — Implemented sync-command fallback fix: ab sync now gives actionable init/update messages, ab update restores missing sync-context.sh, and docs point to ab sync --apply.

2026-05-13 11:35 — Fixed `ab sync` missing-script UX, made `ab update` restore missing `sync-context.sh`, replaced direct apply docs with `ab sync --apply`, and verified targeted sync/update tests.

2026-05-13 11:44 — Verified against `takecare-platform`; found multi-repo repo-array rewrite was dropping executable mode, fixed update ordering and shared writer, and `agentboard sync --apply` now succeeds.

2026-05-13 11:55 — Updated `takecare-platform/CLAUDE.md` with current provider-neutral Agentboard workflow rules and synced `AGENTS.md` plus `GEMINI.md`; final sync check reports all listed repos OK.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
