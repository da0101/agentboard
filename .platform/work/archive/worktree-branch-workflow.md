---
stream_id: stream-worktree-branch-workflow
slug: worktree-branch-workflow
type: feature
status: done
agent_owner: codex
domain_slugs: [new-stream-workflow, commands, templates]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/worktree-branch-workflow
created_at: 2026-05-13
updated_at: 2026-05-13
closure_approved: true
---

# worktree-branch-workflow

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope
- Add a mandatory Git worktree/branch preparation step to the Agentboard workflow before feature or bugfix implementation begins.
- Document Git Flow base branch rules: `feature/*` and `bugfix/*` from `develop`; `hotfix/*` from `master` only when the user explicitly says hotfix.
- Cover multi-repo projects so backend/frontend/mobile/MCP work can happen in separate filesystem worktrees per repo when a stream touches multiple repos.
- Update canonical workflow files, shipped templates, provider entry templates, and skills that operationalize new stream/start workflow.
- Out of scope: implementing automatic worktree creation commands unless research shows existing command support is already available and low-risk.

## Done criteria
- [x] Workflow clearly requires a branch/worktree step before feature/bugfix/hotfix work.
- [x] Base branch rules are explicit: develop for feature/bugfix; master for user-declared hotfix.
- [x] Branch prefixes are explicit: `feature/`, `bugfix/`, `hotfix/`.
- [x] Multi-repo worktree guidance covers separate filesystems per touched repo.
- [x] Tests verify canonical and template/provider instructions contain the rule.
- [x] Manual QA plan included for validating a new stream bootstrap.
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
_Append-only. Format: `2026-05-13 — <decision> — <rationale>`_

- 2026-05-13 — Worktree/local environment prep is mandatory before implementation — it prevents concurrent branch collisions and makes dependency/port blockers visible before coding or QA.

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-05-13 by danilulmashev
- **What just happened:** Implemented mandatory worktree/local environment prep: workflow Stage 1c, provider/skill/template propagation, new-stream branch defaults, decisions/log updates, and focused tests pass.
- **Current focus:** —
- **Next action:** User reviews the workflow behavior; if approved, close stream and commit. Remember sync-command-fallback is also awaiting verification.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-05-13 HH:MM — <what happened>`._

2026-05-13 13:22 — Implemented mandatory worktree/local environment prep: workflow Stage 1c, provider/skill/template propagation, new-stream branch defaults, decisions/log updates, and focused tests pass.

2026-05-13 13:21 — Added Stage 1c worktree/local environment prep, provider/skill/template propagation, new-stream branch defaults, and focused tests for workflow, entry templates, and stream command behavior.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit Report

> **Required:** After every audit request, paste the full standardized report here.
> Do NOT leave the audit only in chat — it must be anchored here so the next session has it.
> Format: `.platform/workflow.md` → Stream / Feature Analysis Protocol → Step 4 template.
> After a clean re-audit (all 🟢), remove this section before stream closure.

_Status: not yet run_
