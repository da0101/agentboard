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
updated_at: 2026-07-02
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

- **Last updated:** 2026-07-02 by danilulmashev
- **What just happened:** Re-audit resolved release blockers: hardened terminal escaping, git process calls, stale-session deletion, event-only stream attribution, hook noise, and checkpoint file-size ratchet; full unit suite passed.
- **Current focus:** —
- **Next action:** Manual VS Code dashboard QA remains pending; release tag v2.4.6 can be cut from main after pushing verified commits.
- **Blockers:** none

## Progress log

_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-07-02 18:07 — Re-audit resolved release blockers: hardened terminal escaping, git process calls, stale-session deletion, event-only stream attribution, hook noise, and checkpoint file-size ratchet; full unit suite passed.

2026-06-29 15:21 — Fixed Claude activity changed-line stats for absolute/sibling-worktree paths: git enrichment now resolves each activity file's own git root before numstat and line-count lookup; installed extension runtime updated.

2026-06-29 15:10 — Softened Claude/Codex provider tinting: fills lowered to 7% alpha and borders to 24%, with installed VS Code extension asset updated.

2026-06-29 15:08 — Removed provider gradients in dashboard/session UI, fixed session-tab activity counts to use selected-session totals, and added Bash dirty-file FileChange fallback so Claude command-driven changes appear in session activity.

2026-06-29 14:59 — Fixed disappearing Claude sessions at the hook layer: event logger now derives stable ids from transcript/conversation/thread payload fields and gives payload ids priority over leaked provider env ids; snapshot helper sanitizes derived ids.

2026-06-29 14:14 — Fixed session-tab layout so the selected session activity feed scrolls internally while header/now/agents stay fixed in the pane; installed extension shell runtime updated.

2026-06-29 14:12 — Added trend graph lifecycle KPIs: buckets now expose New/Deleted series from event data plus repo-local git status; installed VS Code extension runtime updated.

2026-06-29 13:52 — Removed embedded Activity feeds from main dashboard session cards so detailed activity lives only in the session tab.

2026-06-29 13:36 — Added repo-scoped event-only fallback sessions and root-validated closeSession handling after takecare-platform showed Claude events but no session snapshot.

2026-06-29 12:50 — Strengthened provider color treatment in the single-session dashboard path so Claude/Codex differences are visible without needing multiple session cards.

## Open questions

- Resolved 2026-06-29 — v1 stale-session cleanup removes only the runtime session snapshot; process termination remains out of scope.

---

## 🔍 Audit — 2026-07-02

> Supersedes previous audit. Run via Stream / Feature Analysis Protocol — 1 parallel agent.

# 📋 Provider Session Interfaces — Audit Snapshot

> **Stream:** `provider-session-interfaces` · **Date:** 2026-07-02 · **Status:** 🟢 Re-audit clean pending manual QA
> **Repos touched:** `repo-primary`

---

## ⚡ At-a-Glance Scorecard

| Area | repo-primary |
|---|:---:|
| **Implementation** | 🟢 |
| **Tests** | 🟢 |
| **Security** | 🟢 |
| **Code Quality** | 🟢 |
| **Manual QA** | 🟡 pending human VS Code signoff |

**Bottom line:** Prior release-blocking findings are resolved. No new release-blocking issues were found in the current diff. Manual VS Code dashboard QA remains the only non-green item.

## Prior Blocker Verification

| Prior finding | Status | Evidence |
|---|:---:|---|
| Dollar-sign escaping for double-quoted terminal launches | 🟢 Resolved | `escapeForDoubleQuotedCli` now escapes `$` at `extensions/vscode/src/dashboard/prompts.ts:13`; launch paths use it at `extensions/vscode/src/dashboard/messageRouter.ts:106` and `extensions/vscode/src/dashboard/messageRouter.ts:178`; regression test at `extensions/vscode/tests/dashboard-helpers.test.js:316`. |
| Shell-interpolated git commands with workspace/webview paths | 🟢 Resolved | Replaced with `execFileSync` argument arrays at `extensions/vscode/src/dashboard/dataBuilder.ts:439`, `extensions/vscode/src/dashboard/gitActivity.ts:86`, and `extensions/vscode/src/dashboard/messageRouter.ts:66`. |
| `closeSession` / `sessionFiles` path traversal hardening | 🟢 Resolved | Safe session-id allowlist and resolved containment check at `extensions/vscode/src/dashboard/sessionFiles.ts:5` and `extensions/vscode/src/dashboard/sessionFiles.ts:44`; delete path wired through workspace check at `extensions/vscode/src/dashboardPanel.ts:175`; regression test at `extensions/vscode/tests/dashboard-helpers.test.js:385`. |
| Event-only sessions preserve stream | 🟢 Resolved | Event-only session stream now comes from recent session events at `extensions/vscode/src/dashboard/eventOnlySessions.ts:38`; regression test at `extensions/vscode/tests/dashboard-helpers.test.js:398`. |
| Provider UI / event-only / deletion / escaping tests exist | 🟢 Resolved | Provider UI test at `extensions/vscode/tests/dashboard-helpers.test.js:328`; deletion test at `:385`; event-only test at `:398`; escaping test at `:316`; `npm test` script added at `extensions/vscode/package.json:68`. |
| Root unit suite and file-size ratchet | 🟢 Resolved | Root unit suite passed: `PASS: unit (60 files, 490 tests)`. File-size ratchet passed; `checkpoint.sh` is now 462 lines against frozen limit 475 in `tests/unit/file_size_ratchet_test.sh:24`. |

## Healthy Areas

| Area | Notes |
|---|---|
| Provider presentation | Claude/Codex/Gemini UI model is centralized and testable in `extensions/vscode/media/dashboard/providerUi.js:5`; Codex stale cleanup copy remains explicit that it does not terminate Codex or delete work at `:34`. |
| Session deletion safety | Invalid traversal IDs return `false` before unlink, and workspace-root mismatch refuses deletion. |
| Git activity enrichment | The dashboard now uses git argument arrays and per-file git-root resolution, preserving sibling-worktree stats without shell interpolation. |
| Test harness | Extension compile and test entrypoints are now normal commands: `npm run compile`, `npm test`. |
| Diff hygiene | `git diff --check HEAD` passed. |

## Findings

### 🔴 Must Fix
None.

### 🟡 Should Fix / Limitations
| # | Repo | Item |
|---|---|---|
| 1 | repo-primary | Manual QA remains pending. The artifact is present and detailed, but signoff is still `pending human VS Code dashboard verification` at `.platform/work/qa/provider-session-interfaces-manual-qa.md:99`. |

### ⚪ Known Limitations
| # | Limitation |
|---|---|
| 1 | Gemini remains a UI extension point, not a full producer implementation. |
| 2 | This audit did not drive the VS Code webview interactively; it verified code, diff, and automated tests only. |

## Verification Run

| Command | Result |
|---|---|
| `npm run compile` in `extensions/vscode` | ✅ passed |
| `npm test` in `extensions/vscode` | ✅ passed |
| `npm test` at repo root | ✅ passed, 60 files / 490 tests |
| `git diff --check HEAD` | ✅ passed |
