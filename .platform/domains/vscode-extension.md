---
domain_id: dom-vscode-extension
slug: vscode-extension
status: active
repo_ids: [repo-primary]
related_domain_slugs: [orchestration, templates]
created_at: 2026-06-26
updated_at: 2026-06-26
---

# vscode-extension

## What this domain does

This domain owns the Agentboard VS Code extension and the runtime files that feed its live dashboard. It lets a developer see active agent sessions, workstreams, catalog metadata, file activity, cost, model, and staleness inside the editor.

## Backend / source of truth

- `~/.agentboard/sessions/*.json` is the cross-provider live session snapshot source for the dashboard.
- `.platform/events.jsonl` is the per-project activity/event source used by the activity feed and code activity stats.
- Provider hooks and wrappers must normalize to the existing Claude-compatible session/event schemas instead of forcing dashboard-specific provider branches.

## Frontend / clients

- `extensions/vscode/src/dashboardPanel.ts` renders the Live/Catalog dashboard webview.
- `extensions/vscode/src/extension.ts` registers commands, sidebar providers, and dashboard open/refresh behavior.
- `extensions/vscode/src/workspaceRoot.ts` resolves the active Agentboard workspace root.

## API contract locked

- Session JSON must remain provider-neutral enough for Claude and Codex to appear together.
- Event records must stay newline-delimited JSON in `.platform/events.jsonl`.
- Runtime artifacts remain ignored by git; templates and hook scripts are tracked.
- The dashboard should prefer the current VS Code workspace over stale global live metadata.

## Key files

- `extensions/vscode/src/dashboardPanel.ts`
- `extensions/vscode/src/extension.ts`
- `extensions/vscode/src/workspaceRoot.ts`
- `templates/platform/scripts/hooks/status-bridge.js`
- `templates/platform/scripts/hooks/event-logger.sh`
- `templates/platform/scripts/session-track.sh`
- `templates/codex/`
- `templates/root/AGENTS.md.template`

## Decisions locked

- Keep the dashboard data model provider-compatible instead of adding separate Claude/Codex UI paths.
- Keep runtime telemetry local and gitignored.
- Prefer small hook/wrapper adapters that emit the existing session/event formats.
