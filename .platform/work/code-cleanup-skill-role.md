---
stream_id: stream-code-cleanup-skill-role
slug: code-cleanup-skill-role
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [agent-roles-skills]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/code-cleanup-skill-role
created_at: 2026-06-13
updated_at: 2026-06-13
closure_approved: false
---

# code-cleanup-skill-role

## Scope
- Add a reusable cleanup skill that agents use when asked to clean up a whole codebase, a feature, a function, a file, or a folder.
- Add or update a role profile so cleanup requests route to the right senior-agent identity before the skill runs.
- Define a safe cleanup workflow: scan first, classify findings, propose changes, preserve behavior, test, and report evidence.
- Cover targets such as duplicated logic, dead code, oversized files, excessive comments, avoidable complexity, performance hotspots, housekeeping, and maintainability.
- Out of scope until explicitly approved: executing broad cleanup changes without an approved plan, rewriting unrelated architecture, or committing/pushing.

## Done criteria
- [x] Research-backed plan approved by the user before implementation.
- [x] Isolated worktree exists for `feature/code-cleanup-skill-role`, with dependencies and local commands recorded.
- [x] Cleanup skill is added to shipped templates and installed local skill dirs needed for current providers.
- [x] Cleanup role is added or existing role routing is updated, with README/CHEATSHEET/docs updated where user-facing.
- [x] Tests cover skill/role pack integrity and any changed install/update behavior.
- [x] Manual QA or command-level verification confirms a fresh project can discover the role and skill.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if any architectural choices were made.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/Users/danilulmashev/Documents/GitHub/agentboard-code-cleanup-skill-role` | `feature/code-cleanup-skill-role` | `develop` | no install needed; bash CLI with shell tests | `bash tests/unit/roles_pack_test.sh` / focused `bash tests/unit/*_test.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-13 — by codex
- **What just happened:** Implemented and verified `ab-cleanup`, `code-cleanup-engineer`, provider/template routing, main-side Graphify carry-forward, and Graphify cache ignore coverage.
- **Current focus:** Awaiting user verification/review.
- **Next action:** User reviews changes; if accepted, ask explicitly before committing. Do not close/archive until user approves stream closure.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-13 00:00 — Registered stream and domain for cleanup skill/role feature.

## Open questions
_Things blocked on user input. Remove when resolved._
