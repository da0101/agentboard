---
stream_id: stream-codex-dashboard-support
slug: codex-dashboard-support
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [vscode-extension]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/codex-dashboard-support
created_at: 2026-06-20
updated_at: 2026-06-27
closure_approved: false
---

# codex-dashboard-support

Apply the same real-time dashboard treatment to Codex sessions that was built for Claude Code in the 2.1.0 vscode extension release.

## Context

The 2.1.0 release shipped a full live dashboard for Claude Code sessions:
- Session columns with cost, context, branch, last-updated
- WORKFLOW section (collapsible, per-agent status with model/running/done)
- SUB-AGENTS section with staleness detection
- ACTIVITY feed with git diff stats (+N/-N), collapsible, inner scroll
- CATALOG tab with skill/role expand + "used by" session badges
- Status driven by `~/.agentboard/sessions/<id>.json` (written by status-bridge.js hook)
- Events driven by `.platform/events.jsonl` (written by event-logger.sh PostToolUse hook)

Codex needs the same pipeline. The key difference is Codex hooks fire differently — Codex uses `AGENTS.md` for configuration rather than `.claude/settings.json`, and its hook system is separate.

## Scope

- [ ] Understand Codex hook system: what events fire, what payload shape, and how to install hooks into a Codex project
- [ ] Port `status-bridge.js` for Codex: write per-session `~/.agentboard/sessions/<id>.json` with the same schema as the Claude Code bridge so the dashboard backend reads it without changes
- [ ] Port `event-logger.sh` (or write a JS equivalent) for Codex PostToolUse: same `events.jsonl` format — Edit, Write, Bash, AgentStart, WorkflowStart, WorkflowEnd events
- [ ] Port `workflow-parser.js` if Codex has a Workflow-equivalent tool; if not, map the closest analogue
- [ ] Validate that the dashboard `dashboardPanel.ts` sessions loop picks up Codex sessions correctly (provider field may differ — check `provider` in session JSON)
- [ ] Add Codex hook install instructions to `templates/codex/` and `CHEATSHEET.md`
- [ ] Test with a live Codex session: session column appears, activity feeds update, cost/context/branch show correctly
- [ ] Update `AGENTS.md.template` with the hook wiring

## Out of scope

- Any UI changes to the dashboard itself — the frontend is provider-agnostic already
- Gemini support (separate future stream)
- Changing the session JSON schema (must stay compatible with Claude Code)

## Done criteria

- [ ] Research complete: Codex hook API documented with payload shapes
- [ ] `status-bridge` Codex variant written and tested against a real session
- [ ] `event-logger` Codex variant produces valid `events.jsonl` entries
- [ ] Dashboard shows Codex sessions alongside Claude Code sessions in the Live tab
- [ ] ACTIVITY feed shows real file edits from Codex
- [ ] Git diff stats (+N/-N) appear on Codex-edited files
- [ ] Staleness detection works (session idle → sub-agents clear within 10 min)
- [ ] Hook install documented in `templates/codex/` and CHEATSHEET
- [ ] Manual QA: open dashboard with both a Claude Code and Codex session running simultaneously — both appear, both update
- [ ] `.platform/memory/log.md` appended

## Key decisions

_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-20 — Deferred until after Claude Code dashboard is stable — focus on one provider at a time, validate the schema before locking it for cross-provider use.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-codex-dashboard-support` | `feature/codex-dashboard-support` | `develop` | installed: `npm ci` in `extensions/vscode`; root has no lockfile/deps | Root tests: `npm test`; extension compile: `cd extensions/vscode && npm run compile` | none; VS Code extension host/manual reload rather than localhost |

## Manual QA

- Artifact: `.platform/work/qa/codex-dashboard-support-manual-qa.md`
- Status: pending human VS Code/Codex click-through. Automated unit and compile checks passed; live dashboard verification requires a real Codex session in VS Code.

## Reference

- Claude Code bridge: `templates/platform/scripts/hooks/status-bridge.js`
- Claude Code event logger: `templates/platform/scripts/hooks/event-logger.sh`
- Claude Code workflow parser: `templates/platform/scripts/hooks/workflow-parser.js`
- Dashboard backend: `extensions/vscode/src/dashboardPanel.ts` — sessions loop at line ~566
- Codex config template: `templates/codex/`
- `AGENTS.md.template` — Codex agent configuration entry point

## Audit - 2026-06-27

Run via Stream / Feature Analysis Protocol with four parallel audit agents plus local synthesis.

### At-a-glance scorecard

| Area | Status | Notes |
|---|---:|---|
| Implementation | Red | Basic Codex telemetry works, but session identity, stale-root handling, and session-tab agent rendering still have closure blockers. |
| Tests | Yellow | Hook/wrapper unit coverage is good; dashboard ingestion/rendering and live Claude+Codex parity are not covered by the default gate. |
| Security | Green | No secret, auth, or unsafe external-call issue found in the scoped telemetry/dashboard path. |
| Code quality | Red | `extensions/vscode/src/dashboardPanel.ts` is a 1,897-line god module mixing root resolution, event parsing, git/HTTP I/O, terminal focus, rendering, and webview commands. |

### End-to-end wiring

```text
Claude hooks
  -> status-bridge.js / event-logger.sh / workflow-parser.js
  -> ~/.agentboard/sessions/*.json + .platform/events.jsonl + agentboard.hud-status.json
  -> VS Code dashboard

Codex native hooks
  -> templates/platform/scripts/hooks/codex-hook-bridge.js
  -> session-snapshot.js + event-logger.sh
  -> same session/event sinks
  -> VS Code dashboard

Codex wrapper fallback
  -> templates/platform/scripts/codex-ab
  -> session-track.sh heartbeat + file poller
  -> same session/event sinks
  -> VS Code dashboard
```

### What is healthy

- Codex native hooks normalize tool/file/command payloads into the same event contract used by Claude.
- Codex wrapper fallback can create heartbeat snapshots and file-change events when native hooks are absent.
- Session JSONs use the provider-neutral fields the dashboard already expects: provider, model, branch, cost/context, session id, root, timestamps, and shell pid.
- Subagent lifecycle events are mapped into `AgentStart` / `AgentDone`.
- Targeted unit tests pass for `codex_hook_bridge`, `session_track`, `events_test`, `event_logger_skill_role`, `wrapper_model`, `commands_update`, and the existing VS Code helper tests.

### Must fix before closure

1. One real Codex run can fragment into two dashboard sessions when wrapper fallback and native hooks emit different session ids. The wrapper invents `AGENTBOARD_SESSION_ID`, while native hooks derive from the Codex hook payload. The dashboard reads all `~/.agentboard/sessions/*.json` and does not dedupe concurrently updating records.
   - Evidence: `templates/platform/scripts/codex-ab:16`, `templates/platform/scripts/codex-ab:70`, `templates/platform/scripts/hooks/codex-hook-bridge.js:148`, `templates/platform/scripts/hooks/session-snapshot.js:82`, `extensions/vscode/src/dashboardPanel.ts:1154`.

2. Session-tab agents can be misleading or duplicated across tabs. The backend builds per-session `sAgents`, but session-tab frontend mode overrides `fileActivity` with `s0.activity` and does not override `recentAgents` with `s0.agents`, so the agents panel can render the global/current-session list.
   - Evidence: `extensions/vscode/src/dashboardPanel.ts:1308`, `extensions/vscode/src/dashboardPanel.ts:1405`, `extensions/vscode/media/dashboard.js:320`, `extensions/vscode/media/dashboard.js:582`.

3. Generic VS Code windows can still be scoped by stale global `~/.agentboard/live.json` through `DashboardPanel._buildDataSync`, which duplicates root-selection logic instead of consistently using the TTL-checked workspace-root helper.
   - Evidence: `extensions/vscode/src/dashboardPanel.ts:983`, `extensions/vscode/src/workspaceRoot.ts:31`.

4. The default green test path does not execute the dashboard session ingestion/rendering path. Existing extension tests cover helpers, not the Codex session loop, diff enrichment, stale-agent behavior, or session-tab rendering.
   - Evidence: `package.json:6`, `tests/unit.sh:79`, `extensions/vscode/package.json:68`, `extensions/vscode/src/dashboardPanel.ts:1154`.

5. Manual QA remains incomplete. The stream explicitly requires live VS Code verification with Claude Code and Codex sessions running simultaneously; current QA is still pending and Codex-only in places.
   - Evidence: `.platform/work/codex-dashboard-support.md:60`, `.platform/work/qa/codex-dashboard-support-manual-qa.md:19`.

### Should fix soon

1. Root changes propagate only to `DashboardPanel`; sidebar providers keep readonly initial roots and can drift from the dashboard after live-root switching.
   - Evidence: `extensions/vscode/src/extension.ts:22`, `extensions/vscode/src/extension.ts:53`, `extensions/vscode/src/hudProvider.ts:9`, `extensions/vscode/src/sessionsProvider.ts:41`.

2. Wrapper-only fallback misses brand-new untracked files because polling is based on `git diff HEAD` / `git diff --name-only HEAD`.
   - Evidence: `templates/platform/scripts/session-track.sh:186`, `templates/platform/scripts/session-track.sh:203`.

3. Native-hook-only Codex sessions are not explicitly pinned to a stream, so multi-stream repos can fall back to heuristics.
   - Evidence: `templates/platform/scripts/hooks/codex-hook-bridge.js:144`, `templates/platform/scripts/hooks/event-logger.sh:95`, `templates/platform/scripts/codex-ab:20`.

4. Snapshot branch metadata is effectively write-once and can go stale after checkout.
   - Evidence: `templates/platform/scripts/hooks/session-snapshot.js:180`, `templates/platform/scripts/hooks/status-bridge.js:95`.

5. Claude workflow/transcript parity is not implemented for Codex. Codex supports subagent lifecycle events, but no Codex producer currently emits the `WorkflowStart` / `WorkflowEnd` path consumed by the dashboard workflow section.
   - Evidence: `extensions/vscode/src/dashboardPanel.ts:251`, `extensions/vscode/src/dashboardPanel.ts:1105`, `templates/codex/config.toml:36`, `templates/platform/scripts/hooks/codex-hook-bridge.js:153`.

6. Per-subagent activity attribution is incomplete. Normal activity rows have `session_id`, `tool`, and `cmd`/`file`, but do not consistently carry `agent_id` or a stable subagent key. The dashboard can group by session today, but not reliably by subagent inside the session.
   - Evidence: `templates/platform/scripts/hooks/event-logger.sh:144`, `templates/platform/scripts/hooks/event-logger.sh:258`, `extensions/vscode/src/dashboardPanel.ts:1189`, `extensions/vscode/media/dashboard.js:461`.

### Close checklist

- [ ] Choose one authoritative Codex session id, then make wrapper and native hook paths share it or dedupe them deterministically.
- [ ] Fix session-tab rendering to use `s0.agents` for the selected session and update provider-specific empty copy.
- [ ] Add `agent_id` / `agent_label` / parent-session attribution to emitted events, then add a per-subagent activity UI inside session tabs.
- [ ] Route dashboard root selection through the same TTL-checked helper used by workspace-root tests.
- [ ] Propagate root changes to sidebar providers and HUD watchers.
- [ ] Capture untracked new files in wrapper fallback.
- [ ] Pin stream identity for native-hook-only Codex sessions.
- [ ] Refresh branch on each snapshot write.
- [ ] Add dashboard ingestion/rendering tests for Codex session tabs, diff stats, stale clearing, and duplicate-session prevention.
- [ ] Execute manual QA with Claude Code and Codex running simultaneously in VS Code.

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-27 by danilulmashev
- **What just happened:** Fixed VS Code refactor-new context action so it asks for Codex/Claude/Gemini instead of hard-coding Claude, and hot-applied compiled extension files for local dogfooding.
- **Current focus:** —
- **Next action:** Reload the Agentboard panel and verify Refactor in new session opens a provider picker; choose Codex and confirm it launches Codex Code Cleanup through .platform/scripts/codex-ab.
- **Blockers:** none

## Progress log
_Append-only. Auto-trimmed by `ab checkpoint` to last 10 entries._

2026-06-27 13:12 — Fixed VS Code refactor-new context action so it asks for Codex/Claude/Gemini instead of hard-coding Claude, and hot-applied compiled extension files for local dogfooding.

2026-06-27 12:23 — Fixed Claude session invisibility in ESM projects: event logger now refreshes repo-local session snapshots via a CJS runtime copy, and checkpoint legacy-frontmatter failures preserve retry commands.

2026-06-27 10:52 — Fixed raw Codex session activity mismatch: unbridged Codex sessions now carry best-effort workspace activity so KPI file counts and session panel activity agree.

2026-06-27 10:20 — Moved VS Code dashboard session storage from global ~/.agentboard/sessions to per-repo .platform/runtime/agentboard/sessions; provider hooks and installed extension output updated.

2026-06-27 09:23 — Fixed raw Codex invisibility: VS Code dashboard now detects unbridged local Codex CLI processes by workspace cwd and shows them as raw Codex sessions when no bridged Codex session exists.

2026-06-27 08:42 — Fixed stale HUD ghost status: dashboard ignores workspace/global HUD snapshots older than 30 minutes, preventing old Opus/Claude status from showing as live.

2026-06-27 08:09 — Fixed live dashboard UI state reset by persisting stream/section/KPI/session fold state in VS Code webview state and hot-updated the installed extension copy.

2026-06-27 07:55 — Installed the rebuilt VS Code extension runtime locally and added session-tab disposal so sessions from another workspace cannot linger after root filtering.

2026-06-27 07:45 — Fixed VS Code dashboard cross-project session leak: active sessions from ~/.agentboard/sessions are now filtered by canonical workspace root before rendering.

2026-06-27 07:36 — Fixed dashboard session activity Git enrichment so untracked created files are expanded individually, emitted as synthetic new rows, and sorted into the visible feed.
