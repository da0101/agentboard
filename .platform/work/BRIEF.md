# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** none
**Status:** idle
**Stream file:** none

---

## What we're building

No active stream is currently in progress.

## Why

The previous active streams were completed, verified, and archived. The next agent should start from `work/ACTIVE.md` and the durable memory files.

## What done looks like

- `work/ACTIVE.md` has no active streams
- Completed stream context lives in `work/archive/`
- Durable decisions and learnings are captured in `.platform/memory/`

## Architecture decisions locked

- No active-stream decisions pending.

## Current state

Ready for the next task.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load files relevant to the next task. Do not auto-load archived streams.

**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `.platform/work/ACTIVE.md`
- `.platform/memory/log.md`
