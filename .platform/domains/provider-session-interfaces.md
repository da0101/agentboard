---
domain_id: dom-provider-session-interfaces
slug: provider-session-interfaces
status: active
repo_ids: [repo-primary]
related_domain_slugs: [vscode-extension]
created_at: 2026-06-29
updated_at: 2026-06-29
---

# provider-session-interfaces

## What this domain does

This domain owns provider-specific session management surfaces in the Agentboard
VS Code extension: Claude, Codex, and future Gemini session views, stale-session
handling, provider-specific actions, and shared UI foundations.

## Backend / source of truth

- `.platform/runtime/agentboard/sessions/*.json` is the preferred per-project
  live session source.
- `~/.agentboard/sessions/*.json` may still exist for older/global producers and
  must be filtered carefully to avoid stale cross-project ghosts.
- `.platform/events.jsonl` remains the project activity feed.
- Provider-specific UI may branch on `session.provider`, but session/event file
  contracts should stay normalized so producers do not need dashboard-specific
  schemas.

## Frontend / clients

- `extensions/vscode/src/dashboardPanel.ts` builds the dashboard data payload.
- `extensions/vscode/src/dashboard/*` contains extracted data, provider launch,
  event, session, and formatting helpers.
- `extensions/vscode/media/dashboard.js` and `extensions/vscode/media/dashboard/*`
  render the webview UI.
- Provider-specific session interfaces should share core primitives while
  isolating provider behavior, copy, actions, and visual themes.

## API contract

- Session records must keep a stable provider field: `claude`, `codex`,
  `gemini`, or a documented fallback.
- Stale detection must be deterministic and visible in the UI.
- Closing or clearing stale sessions must not delete user work or terminate a
  live process unless the action explicitly says so and has a safe backend path.
- Provider-specific folders may exist for UI organization, but shared schema
  parsing, freshness rules, and event normalization should remain centralized.

## Key files

- `extensions/vscode/src/dashboardPanel.ts`
- `extensions/vscode/src/dashboard/dataBuilder.ts`
- `extensions/vscode/src/dashboard/sessionSummary.ts`
- `extensions/vscode/src/dashboard/providerLaunch.ts`
- `extensions/vscode/src/dashboard/types.ts`
- `extensions/vscode/media/dashboard.js`
- `extensions/vscode/media/dashboard/sessionCard.js`
- `extensions/vscode/media/dashboard/agentsPanel.js`
- `extensions/vscode/media/dashboard/activityRow.js`
- `extensions/vscode/media/dashboard/core.js`

## Decisions locked

- Keep storage contracts provider-normalized.
- Allow provider-specific UI modules when provider behavior materially differs.
- Treat stale-session cleanup as a separate behavior from killing a live agent.
