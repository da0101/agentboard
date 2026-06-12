---
stream_id: stream-tool-quality-uplift
slug: tool-quality-uplift
type: feature
status: done
agent_owner: claude-code
domain_slugs: [orchestration, commands]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/tool-quality-uplift
created_at: 2026-04-28
updated_at: 2026-04-28
closure_approved: true
---

# tool-quality-uplift

Move agentboard from 6.5/10 to 9.5/10 by closing the four concrete gaps
identified in the session audit.

## Scope

- Auto session ID generation in `codex-ab`/`gemini-ab` so lock system works
  correctly with real parallel sessions (no more `anonymous` collisions)
- Codex/Gemini log-reason reminder: on wrapper exit, detect FileChange events
  without a subsequent Reason event since session start, print a reminder list
- Domain auto-update suggestions: during `ab close` harvest checklist, show
  which files touched in this stream aren't mentioned in domain files
- Fix `watch_install_test.sh` pre-existing plist path failure

Out of scope:
- Full automation of domain file updates (LLM writes them, not bash)
- Claude Code hook improvements (already solid)
- Any new commands or new runtime dependencies

## Done criteria

- [x] `codex-ab`/`gemini-ab` export `AGENTBOARD_SESSION_ID` at startup; two
      concurrent sessions get distinct IDs; `lock acquire` uses them correctly
- [x] Wrapper exit handler prints unreasoned-FileChange reminder list when
      ≥1 FileChange events since session start have no following Reason event
- [x] `ab close` harvest checklist includes "Domain gap check" section listing
      files touched by stream commits not referenced in domain file
- [x] `watch_install_test.sh` passes
- [x] Full `tests/unit.sh` runs with no new failures
- [x] `tests/unit/lock_test.sh` still passes (regression guard)
- [x] `.platform/memory/log.md` appended

## Key decisions

2026-04-28 — Use timestamp+PID (`$(date +%s)-$$`) for session ID — UUID not
available in bash 3.x without external tools; timestamp+PID is collision-safe
for the concurrent-session use case.

## Resume state

- **Last updated:** 2026-04-28 — by claude-code
- **What just happened:** all 4 phases executed, committed as `87e59d2`; domain doc updated; awaiting human verification
- **Current focus:** awaiting-verification
- **Next action:** human reviews test results + feature behaviour; if satisfied set `closure_approved: true` and run `ab close tool-quality-uplift --confirm`
- **Blockers:** none

## Progress log

- 2026-04-28 — Phase 1: fixed `watch_install_test.sh` (stub rename + systemd unit name)
- 2026-04-28 — Phase 2: added `_ab_check_unreasoned_changes()` to session-track.sh; wired into codex-ab + gemini-ab exit blocks
- 2026-04-28 — Phase 3: added `_close_print_domain_gap()` to close.sh; called from harvest checklist
- 2026-04-28 — Phase 4: updated orchestration.md; committed `feat: log-reason exit reminder, domain gap check, watch test fixes`

## Open questions

---

## 🔍 Audit Report

_Status: not yet run_
