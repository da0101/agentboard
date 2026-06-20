# Agentboard — VS Code Extension

Live dashboard for your AI agent sessions — multi-session grid, sub-agent tracking, workflow status, file activity, and your full skill/role catalog, all without leaving VS Code.

## What it shows

### Live tab

The **Live** tab is a real-time dashboard that updates every 5 seconds (and instantly on file change):

- **NOW block** — the last tool call the active agent made (file, bash command, or skill), how long ago, and a warning badge when an operation has been running silently for more than 90 seconds.
- **Session grid** — one column per active Claude Code session. Each column shows:
  - Model · branch · session nickname
  - Cost / Time elapsed / Context remaining / Current stream
  - File and bash activity feed with git diff stats (`+N` added, `-N` deleted)
  - WORKFLOW section: agent list with a blue pulsing dot (running) or green dot + checkmark (done), model badge, and result preview
  - SUB-AGENTS section: agents dispatched in this session with staleness detection (30 min per-agent timeout; 10 min session-idle timeout collapses all pending agents to done)
  - ACTIVITY section (inner scroll, 260 px): every file edit and bash command logged by the PostToolUse hook, deduplicated and sorted most-recent-first
- **Active streams** row — one row per non-closed stream from `.platform/work/`, with status dot and type badge; click any stream to open it in the editor.

### Catalog tab

Three columns, each expandable:

| Column | Source | Count |
|---|---|---|
| **Skills** | `.claude/skills/` | ~40 |
| **Roles** | `.platform/roles/` | ~26 |
| **Commands** | Built-in CLI reference | 14 |

Each card shows the name, one-line description, and "used by" session nickname badges (generated from current session events). Clicking a card expands the full prose from `SKILL.md`.

## Requirements

- VS Code 1.85 or later
- A project initialised with `agentboard init` (workspace must contain `.platform/work/ACTIVE.md`)
- Agentboard hooks installed (`agentboard install-hooks`) — the extension reads `.platform/events.jsonl` written by the PostToolUse hook and `~/.agentboard/sessions/<id>.json` written by the status-bridge Stop hook

The extension activates automatically when VS Code opens a workspace that contains `.platform/work/ACTIVE.md`.

## Installation

### From the packaged VSIX (recommended)

```bash
cd ~/code/agentboard/extensions/vscode
npm install
npm run compile
npx @vscode/vsce package
code --install-extension agentboard-2.1.0.vsix
```

Then open any project that has been initialised with `agentboard init`.

### Development mode

Open `extensions/vscode/` in VS Code and press **F5**. This launches a new Extension Development Host window with the extension loaded — no packaging step required.

## How to open the dashboard

Once installed, open the dashboard with:

- Command palette (`Cmd+Shift+P` / `Ctrl+Shift+P`): **Agentboard: Open Dashboard**
- Or: the Agentboard icon in the Activity Bar → sidebar panels remain available as a lighter alternative

## How data flows in

| Data source | What it feeds |
|---|---|
| `~/.agentboard/sessions/<id>.json` | Session grid columns (cost, context %, model, branch, start time) |
| `.platform/events.jsonl` | Activity feed, sub-agent list, workflow detection, skill/role usage badges |
| `.platform/work/*.md` | Active streams row |
| `.claude/skills/` | Catalog — Skills column |
| `.platform/roles/` | Catalog — Roles column |
| `~/.agentboard/live.json` (optional) | Global live pointer — lets the dashboard follow whichever project is active |

The `status-bridge.js` Stop hook writes each session file. The `event-logger.sh` PostToolUse hook appends to `events.jsonl`. Both are installed by `agentboard install-hooks`.

The extension watches `agentboard.hud-status.json` for file-system changes and refreshes instantly; everything else polls every 5 seconds.

## Commands

| Command | Description |
|---|---|
| `Agentboard: Open Dashboard` | Open the Live/Catalog webview panel |
| `Agentboard: Refresh Status` | Force-refresh all panels |
| `Agentboard: Open Brief` | Open `.platform/work/BRIEF.md` in the editor |

## Sidebar panels (lightweight alternative)

The extension also contributes five sidebar tree views in the Agentboard Activity Bar icon:

| Panel | Source |
|---|---|
| **Session Status** | `agentboard.hud-status.json` |
| **Streams** | `.platform/work/ACTIVE.md` |
| **Catalog** | `.claude/skills/` + `.platform/roles/` |
| **Sessions** | Control plane HTTP (`ab start`) with HUD file fallback |
| **Worktrees** | Control plane HTTP or `git worktree list` |

Sessions and Worktrees fall back gracefully when the control plane is not running.

## Screenshot

<!-- TODO: add screenshot of Live tab (multi-session grid) and Catalog tab -->

## License

MIT
