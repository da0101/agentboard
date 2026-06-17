# Agentboard — VS Code Extension

Live agentboard session status in a VS Code sidebar. Read-only; makes no writes and calls no CLI.

## Activation

Auto-activates when the workspace contains `.platform/work/ACTIVE.md`.

## Sidebar panels

- **Session Status** — model, branch, token pressure, active agents, todos in-progress, CI status, cost, risk flags, open PRs. Sourced from `agentboard.hud-status.json` in the workspace root.
- **Streams** — one row per stream parsed from `.platform/work/ACTIVE.md`.

## How the HUD file is populated

The `memory-persist.sh` Stop hook (run by the harness after each agent session) emits `agentboard.hud-status.json`. The extension watches for changes and refreshes automatically.

## Commands

| Command | Description |
|---|---|
| `Agentboard: Refresh Status` | Force-refresh both panels |
| `Agentboard: Open Brief` | Open `.platform/work/BRIEF.md` in the editor |
