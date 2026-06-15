---
stream_id: stream-manual-qa-artifact-gate
slug: manual-qa-artifact-gate
type: feature
status: done
agent_owner: codex
domain_slugs: [manual-qa-artifacts, new-stream-workflow, qa-self-heal]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/manual-qa-artifact-gate
created_at: 2026-06-15
updated_at: 2026-06-14
closure_approved: true
---

# manual-qa-artifact-gate

## Scope
- Strengthen Agentboard's manual QA workflow from an optional chat plan into a
  required markdown QA manual artifact for shippable work that needs human or
  app-driving verification.
- Make the artifact a hard gate before commit, push, release, and stream
  closure unless manual QA is explicitly documented as not required.
- Use the referenced `cashflow-guard` QA manuals as inspiration for detailed
  click-by-click coverage and expected results.
- Update provider-neutral workflow/template/skill surfaces so Claude, Codex,
  Gemini, human QA, and Maestro-style testers follow the same rule.
- Out of scope until approved: building a new QA runner, integrating directly
  with Maestro APIs, or auto-generating app-specific tests from code.

## Done criteria
- [x] New stream and domain registered.
- [x] Isolated feature worktree exists and local environment recorded.
- [x] Compact local research covers existing Agentboard manual QA rules and the
      referenced `cashflow-guard` QA documents.
- [x] Targeted external research completed for QA manual / test procedure best
      practices.
- [x] Plan approved before implementation.
- [x] Workflow and provider templates require a durable manual QA markdown
      artifact before commit/push/release/closure when applicable.
- [x] QA-related skills/roles guide agents to create detailed click-by-click QA
      manuals usable by human testers or Maestro/app-driving agents.
- [x] Contract tests cover the new manual QA artifact gate.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if this becomes a durable process decision.
- [x] Manual QA artifact created and archived at
      `.platform/work/archive/qa/manual-qa-artifact-gate-manual-qa.md`.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-15 — Manual QA artifacts are stream-scoped operational state — active
artifacts live under `.platform/work/qa/` and move to
`.platform/work/archive/qa/` when the stream closes so QA history is preserved.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-manual-qa-artifact-gate` | `feature/manual-qa-artifact-gate` | `origin/main` | no install needed; bash CLI with shell tests | `bash tests/unit.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-14 by danilulmashev
- **What just happened:** Implemented the Manual QA artifact gate, added the stream QA artifact, recorded the archive/learning follow-up in backlog, and verified focused contracts plus full unit suite.
- **Current focus:** —
- **Next action:** Await human verification/closure approval; do not archive or commit until the owner confirms the stream is done and requests commit/push.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-14 21:42 — Implemented the Manual QA artifact gate, added the stream QA artifact, recorded the archive/learning follow-up in backlog, and verified focused contracts plus full unit suite.

2026-06-14 20:59 — Registered stream/domain/worktree, reviewed current QA workflow surfaces and cashflow QA manuals, and completed local/external research for the Manual QA artifact gate.

2026-06-15 00:00 — Registered manual QA artifact gate stream and domain.

## Open questions
_Things blocked on user input. Remove when resolved._

None.
