---
stream_id: stream-provider-session-interfaces
slug: provider-session-interfaces
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [provider-session-interfaces, vscode-extension]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/provider-session-interfaces
created_at: 2026-06-29
updated_at: 2026-06-29
closure_approved: false
---

# provider-session-interfaces

Build provider-specific session interfaces for Agentboard's VS Code dashboard so
Claude, Codex, and future Gemini sessions can expose the right stale-session
controls, visual treatment, and interaction model without duplicating the shared
dashboard foundation.

## Scope

- Introduce a folder/module structure that separates shared dashboard UI/function
  primitives from provider-specific session interfaces.
- Add provider-specific session presentation patterns for Claude and Codex first,
  with a clear Gemini extension point but no full Gemini implementation unless
  the existing data supports it.
- Add stale-session controls focused on closing/clearing stale Codex sessions
  safely, without conflating cleanup with terminating live work.
- Color-code provider surfaces conservatively: Claude orange, Codex blue, Gemini
  distinct but future-ready.
- Preserve normalized session/event storage and existing dashboard data contracts.

## Out of scope

- Replacing the entire dashboard UI.
- Changing hook payload schemas unless research proves the current contract is
  insufficient.
- Committing or pushing without explicit user approval.

## Done criteria

- [x] Research confirms local dashboard/session architecture and relevant provider UX patterns.
- [x] Proposed shared/provider folder split is implemented without regressing existing dashboard behavior.
- [x] Claude and Codex session interfaces have distinct theme/copy/action patterns.
- [x] Stale Codex sessions can be identified and closed/cleared through a safe UI path.
- [x] Gemini has a documented extension point or minimal placeholder where supported by data.
- [x] Targeted unit/compile checks pass.
- [x] Manual QA artifact exists for dashboard click-through and stale-session behavior.
- [ ] `.platform/memory/log.md` appended if this stream is closed.
- [x] `decisions.md` updated if architectural choices are locked.

## Key decisions

_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-29 — Provider-specific UI modules may coexist with normalized storage — Claude and Codex have different interaction models, but duplicated telemetry schemas would make producers brittle.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-provider-session-interfaces` | `feature/provider-session-interfaces` | `develop` | installed: `npm ci` in `extensions/vscode`; root has no lockfile/deps | Extension compile/watch: `cd extensions/vscode && npm run compile` / `npm run watch` | none; VS Code extension host/manual reload rather than localhost |

## Manual QA

- Required: dashboard session UI and stale-session behavior need human/app-driving verification.
- Artifact: `.platform/work/qa/provider-session-interfaces-manual-qa.md`
- Status: pending human VS Code dashboard verification.

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-29 by danilulmashev
- **What just happened:** Fixed Claude activity changed-line stats for absolute/sibling-worktree paths: git enrichment now resolves each activity file's own git root before numstat and line-count lookup; installed extension runtime updated.
- **Current focus:** —
- **Next action:** Reload VS Code and refresh Agentboard; Claude activity rows pointing at frontend worktree files should show +/- changed-line stats when those files are dirty.
- **Blockers:** none

## Progress log

_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-29 15:21 — Fixed Claude activity changed-line stats for absolute/sibling-worktree paths: git enrichment now resolves each activity file's own git root before numstat and line-count lookup; installed extension runtime updated.

2026-06-29 15:10 — Softened Claude/Codex provider tinting: fills lowered to 7% alpha and borders to 24%, with installed VS Code extension asset updated.

2026-06-29 15:08 — Removed provider gradients in dashboard/session UI, fixed session-tab activity counts to use selected-session totals, and added Bash dirty-file FileChange fallback so Claude command-driven changes appear in session activity.

2026-06-29 14:59 — Fixed disappearing Claude sessions at the hook layer: event logger now derives stable ids from transcript/conversation/thread payload fields and gives payload ids priority over leaked provider env ids; snapshot helper sanitizes derived ids.

2026-06-29 14:14 — Fixed session-tab layout so the selected session activity feed scrolls internally while header/now/agents stay fixed in the pane; installed extension shell runtime updated.

2026-06-29 14:12 — Added trend graph lifecycle KPIs: buckets now expose New/Deleted series from event data plus repo-local git status; installed VS Code extension runtime updated.

2026-06-29 13:52 — Removed embedded Activity feeds from main dashboard session cards so detailed activity lives only in the session tab.

2026-06-29 13:36 — Added repo-scoped event-only fallback sessions and root-validated closeSession handling after takecare-platform showed Claude events but no session snapshot.

2026-06-29 12:50 — Strengthened provider color treatment in the single-session dashboard path so Claude/Codex differences are visible without needing multiple session cards.

2026-06-29 11:51 — Implemented provider-specific session UI, safe stale Codex snapshot cleanup wording, focused tests, decision record, and manual QA artifact.

## Open questions

- Resolved 2026-06-29 — v1 stale-session cleanup removes only the runtime session snapshot; process termination remains out of scope.
