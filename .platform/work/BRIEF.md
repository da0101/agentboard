# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** event-log-dedup
**Status:** awaiting-verification
**Stream file:** `work/event-log-dedup.md`

---

## What we're building

We are hardening non-Claude session tracking so `FileChange` events are not replayed by every live wrapper that sees the same dirty worktree. The fix keeps the event log usable for handoff without losing legitimate later edits to the same file.

## Why

Duplicate file-change rows pollute `.platform/events.jsonl`, make activity attribution noisy, and erode trust in the log as a real handoff surface.

## What done looks like

- Concurrent Codex/Gemini pollers emit one `FileChange` row per distinct dirty file state
- Later edits to the same file still produce new rows when the diff changes
- Tracker regressions and runtime ignore coverage are updated together

## Architecture decisions locked

- File-change dedup uses shared persisted diff-state under `.platform/`, not per-process memory
- The tracker remains daemon-optional; dedup works in the poller path before events hit the logger

## Current state

The tracker script now persists per-file diff fingerprints and rewrites that state on each poll, so concurrent wrappers coordinate instead of replaying the same dirty snapshot. Focused tracker and doctor tests pass; the remaining step is user verification in another repo.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load the files listed here. Everything else is out of scope for this feature.
> Prefer `.platform/domains/<name>.md` files (cross-layer, focused) over repo-wide files.
> Repo files (`backend.md`, `admin.md`, etc.) are conventions — load only if you need to understand patterns.

- `.platform/domains/orchestration.md` — relevant domain for this stream
- `templates/platform/scripts/session-track.sh` — shared non-Claude file-change poller
- `tests/unit/session_track_test.sh` — tracker regressions

**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `templates/platform/scripts/session-track.sh`
- `.platform/scripts/session-track.sh`
- `tests/unit/session_track_test.sh`
