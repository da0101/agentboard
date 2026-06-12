---
domain_id: dom-orchestration
slug: orchestration
status: active
repo_ids: [repo-primary]
related_domain_slugs: []
created_at: 2026-04-18
updated_at: 2026-04-28
---

# orchestration

Cross-provider coordination layer. Gives Claude Code, Codex, and Gemini a shared real-time view of what each other is doing and a session-scoped file-lock queue so they can work in parallel without silently colliding on the same file.

## What this domain does

Captures every tool call, file change, and session lifecycle event from all AI providers into a single ordered stream. It also coordinates session-scoped file locks through the daemon so concurrent agents can queue for the same file instead of overwriting each other. On wrapper exit, it reminds the agent to log reasons for any file changes that lack a matching Reason event in the session log.

## Backend / source of truth

- `templates/platform/scripts/hooks/event-logger.sh` — writes events (direct JSONL or HTTP POST to daemon)
- `templates/platform/scripts/session-track.sh` — SessionStart/End + file-change poller for non-Claude providers; `_ab_check_unreasoned_changes` scans events.jsonl on wrapper exit and lists any file changed without a Reason event
- `bin/agentboard-daemon.js` — Node HTTP server: POST /event, GET /events, GET /health, POST/DELETE/GET lock endpoints
- `lib/agentboard/commands/lock.sh` — CLI lock acquire/release/list path for Codex/Gemini and manual workflows
- `templates/platform/scripts/hooks/pre-tool-use-lock.sh` — Claude pre-write lock acquire path
- `templates/platform/scripts/hooks/post-tool-use-unlock.sh` — Claude post-write lock release path
- `.platform/events.jsonl` — append-only ground truth; never mutated, only appended
- `.platform/.file-change-state.tsv` — last emitted diff fingerprint per tracked file; lets concurrent pollers dedupe `FileChange` events
- `.platform/.file-locks.json` — persisted lock and queue state
- `.platform/.daemon-port` — ephemeral; written by daemon on start, deleted on stop

## Frontend / clients

- `templates/platform/scripts/codex-ab` — sources session-track.sh, prints lock discipline, queries events tail before launch
- `templates/platform/scripts/gemini-ab` — same as codex-ab
- `lib/agentboard/commands/events.sh` — CLI read path (tail, since, stream, stats, clear, path)
- `lib/agentboard/commands/daemon.sh` — CLI daemon management (start, stop, status, logs)
- `templates/root/.claude/settings.json` — wires Claude PreToolUse/PostToolUse lock hooks

## API contract locked

- `POST /event` — body is any JSON; daemon enriches + appends to events.jsonl; returns 204
- `GET /events?since=<ISO>&stream=<slug>&tool=<name>&limit=<n>` — returns JSON array
- `GET /health` — returns `{"pid":N,"uptime":N,"events":N}`
- `POST /lock` — body includes `file`, `provider`, and `session_id`; returns 200 when acquired or 202 when queued
- `DELETE /lock` — body includes `file`, `provider`, and `session_id`; only the holding session releases the lock
- `GET /locks` — returns holder plus queue metadata for current locks
- Port file: `.platform/.daemon-port` — single line, integer port number
- Daemon is optional: event-logger.sh falls back to direct JSONL if daemon unreachable

## Key files

- `bin/agentboard-daemon.js`
- `templates/platform/scripts/hooks/event-logger.sh`
- `templates/platform/scripts/hooks/pre-tool-use-lock.sh`
- `templates/platform/scripts/hooks/post-tool-use-unlock.sh`
- `templates/platform/scripts/session-track.sh`
- `templates/platform/scripts/codex-ab`
- `templates/platform/scripts/gemini-ab`
- `lib/agentboard/commands/daemon.sh`
- `lib/agentboard/commands/events.sh`
- `lib/agentboard/commands/lock.sh`

## Decisions locked

- Node built-ins only (no npm). Daemon is single-file, zero-dependency.
- Daemon is always optional: every client falls back to direct JSONL append on connection failure.
- Port is dynamic (OS-assigned), written to `.platform/.daemon-port` — never hardcoded.
- events.jsonl is append-only ground truth — daemon writes there, not to a separate DB.
- Daemon auto-started by wrappers, not by `agentboard init` — only when a session begins.
- Lock ownership is session-scoped; provider names are descriptive metadata, not the lock key.
- `AGENTBOARD_SESSION_ID` is auto-generated in each wrapper as `${provider}-$$-$(date +%s)` — unique per process invocation. `_lock_session_id` uses `${provider}-anonymous` as fallback when `AGENTBOARD_SESSION_ID` is unset, matching the daemon's own `normalizeSessionId` logic so acquire/release always share the same key.
- Non-Claude `FileChange` dedup is based on persisted file diff state, not per-wrapper memory, so overlapping wrappers do not replay the same dirty snapshot.
- `_ab_check_unreasoned_changes` is called at wrapper exit (before `SessionEnd`) — it finds FileChange events for the current session without a later Reason event for the same file and prints a reminder with `ab log-reason` instructions.
