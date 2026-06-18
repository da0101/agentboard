# Agentboard — VS Code Extension

Live session status, stream tracking, skill/role catalog, active agents, and git worktrees — all in a VS Code sidebar.

## Requirements

- VS Code 1.85+
- A project initialised with `agentboard init` (workspace must contain `.platform/`)

## Installation

```bash
cd ~/Documents/GitHub/agentboard/extensions/vscode
npm install
npm run compile
npx @vscode/vsce package
code --install-extension agentboard-0.1.0.vsix
```

Open any project that has `.platform/` — the agentboard icon appears in the Activity Bar automatically.

## Sidebar panels

| Panel | Source | Notes |
|---|---|---|
| **HUD** | `agentboard.hud-status.json` | Model, branch, token pressure, CI status, cost, risk flags, open PRs |
| **Streams** | `.platform/work/ACTIVE.md` | One row per active stream + next action |
| **Catalog** | `.claude/skills/` + `.platform/roles/` | Skills, Roles, and Commands — counts + names |
| **Sessions** | Control plane HTTP (`ab start`) | Live agent sessions with status, role, stream |
| **Worktrees** | Control plane HTTP or `git worktree list` | Active git worktrees per stream |

Sessions and Worktrees fall back gracefully when the control plane is not running — Sessions shows an "ab start" prompt, Worktrees reads `git worktree list` directly.

## Control plane (Sessions + Worktrees panels)

The control plane is a Node.js daemon that tracks agent sessions and manages git worktrees:

```bash
# Start the daemon (required for live Sessions + Worktrees data)
ab start

# Check running sessions
ab sessions

# Delegate a task to the best-matched role
ab delegate "refactor the auth middleware to use JWT"

# Manage worktrees
ab worktree list
ab worktree new my-stream-slug

# Stop the daemon
ab stop
```

The daemon runs on `127.0.0.1:7842` (override with `AGENTBOARD_PORT`). It writes `agentboard.hud-status.json` on every state change so the HUD panel updates automatically.

## How the HUD file is populated

Three sources write `agentboard.hud-status.json`:

1. **Control plane** (`ab start`) — updates `active_agents`, `cost`, `context` on every session change
2. **memory-persist.sh** Stop hook — writes a full snapshot at the end of each Claude Code session
3. Manual: `curl -s -X POST -d '{"context":{"branch":"main"}}' http://127.0.0.1:7842/hud`

The extension watches for file changes and refreshes automatically — no polling, instant on save.

## Commands

| Command | Description |
|---|---|
| `Agentboard: Refresh Status` | Force-refresh all panels |
| `Agentboard: Open Brief` | Open `.platform/work/BRIEF.md` in the editor |

## Development mode

Open `extensions/vscode/` in VS Code and press **F5** — launches a new Extension Development Host window with the extension loaded. No packaging needed.
