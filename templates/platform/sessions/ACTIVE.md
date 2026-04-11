# Active Sessions

> **Purpose:** coordinate parallel AI sessions (Claude Code + Codex CLI + Gemini CLI) working on this project simultaneously.
> **Read this at session start. Clear your row at session end.**

---

## Active claims

| start_time       | agent        | repo             | area              | task_summary           | eta     | status |
|------------------|--------------|------------------|-------------------|------------------------|---------|--------|
| _(empty)_        |              |                  |                   |                        |         |        |

## Collision rules

- **Hard collision** (same file) → second session stops, negotiates via the founder or a coordination channel
- **Soft collision** (same repo, different files) → allowed, but commit frequently and pull main before push
- **Cross-repo** → allowed freely, this is the intended parallel mode

## Handoff protocol

When you pause mid-task:
1. Update your row's `status` to `paused`
2. Append to `.platform/log.md` what you did + what's left
3. Commit your WIP with a clear message

When you pick up someone else's paused work:
1. Read their log entry
2. Pull the latest main
3. Update the row's `agent` to you
4. Reset `status` to `active`

## How to claim

```bash
agentboard claim "<task summary>"
```

Or edit this file directly:
- Add a row with your start time, agent name, repo, area (file or folder), task, ETA, and `active` status.

## How to release

```bash
agentboard release
```

Or delete your row from the table.
