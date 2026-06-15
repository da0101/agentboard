---
stream_id: stream-qa-execution-journal
slug: qa-execution-journal
type: feature
status: done
agent_owner: codex
domain_slugs: [manual-qa-artifacts, qa-self-heal]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/qa-execution-journal
created_at: 2026-06-15
updated_at: 2026-06-15
closure_approved: true
---

# qa-execution-journal

## Scope
- Extend the Manual QA / QA self-heal process so any LLM-driven interactive QA
  session using Maestro, browser automation, Playwright, or similar app-driving
  tools records a chronological execution journal.
- The journal must document what the agent did, what it observed, successful
  tests, bugs/errors, diagnosis, fixes, human blockers, retests, and remaining
  risk.
- Make the rule provider-neutral for Codex, Claude, Gemini, human QA, and
  Maestro-style testers.
- Keep it bounded: this stream adds the process/template/test contract, not a
  new RAG/archive system or direct Maestro integration.

## Done criteria
- [x] New stream registered.
- [x] Existing related domains reviewed and updated with the execution-journal
      contract.
- [x] Isolated feature worktree exists and local environment recorded.
- [x] Compact local research covers current Manual QA artifact and QA self-heal
      surfaces.
- [x] Targeted external research completed for session notes / exploratory QA
      logging best practices.
- [x] Plan approved before implementation.
- [x] Workflow, provider templates, QA skills, and QA roles require a
      chronological execution journal for interactive LLM-driven QA.
- [x] Contract tests cover the new execution-journal rule.
- [x] Manual QA artifact or explicit not-required reason recorded for this
      process-only stream.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if this becomes a durable process decision.
- [x] Manual QA artifact archived at
      `.platform/work/archive/qa/qa-execution-journal-manual-qa.md`.
- [x] QA execution journal not required for this stream because no app was
      driven interactively; verification is by shell contract tests.
- [x] Focused contract tests, `git diff --check`, and full unit suite pass.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-15 — Interactive LLM-driven QA needs a chronological execution journal
— the Manual QA artifact says what should be tested, while the journal records
what the agent actually did, observed, fixed, retested, passed, skipped, or
escalated.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-qa-execution-journal` | `feature/qa-execution-journal` | `origin/main` | no install needed; bash CLI with shell tests | `bash tests/unit.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-15 by danilulmashev
- **What just happened:** Implemented QA execution journal rule across workflow, provider entries, QA skills/roles, domains, tests, memory, and stream QA artifact; focused tests and full unit suite pass.
- **Current focus:** —
- **Next action:** Await owner verification; do not archive or commit until explicitly requested.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-15 07:57 — Implemented QA execution journal rule across workflow, provider entries, QA skills/roles, domains, tests, memory, and stream QA artifact; focused tests and full unit suite pass.

2026-06-15 07:22 — Registered the stream, updated manual QA/QA self-heal domains, completed local and external research, and proposed the execution-journal implementation plan.

2026-06-15 00:00 — Registered QA execution journal stream and updated related domains.
2026-06-15 00:00 — Completed local/external research for QA execution journals and proposed implementation plan.
2026-06-15 00:00 — Implemented QA execution journal contract and verified focused tests plus full unit suite.

## Open questions
_Things blocked on user input. Remove when resolved._

None.
