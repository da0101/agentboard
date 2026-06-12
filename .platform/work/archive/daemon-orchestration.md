---
stream_id: stream-daemon-orchestration
slug: daemon-orchestration
type: feature
status: done
agent_owner: claude-code
domain_slugs: [orchestration]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/daemon-orchestration
created_at: 2026-04-18
updated_at: 2026-04-18
closure_approved: true
---

# daemon-orchestration

Node.js local HTTP daemon for cross-provider event serialization, real-time shared state, and file-level conflict prevention. Enables Claude Code + Codex (or any pair) to run in parallel with shared event history and a session-scoped file lock queue to reduce edit collisions.

## Scope

### Phase 1 — Event daemon (DONE ✅)
- `bin/agentboard-daemon.js` — single-file Node HTTP daemon, zero npm deps
- `lib/agentboard/commands/daemon.sh` — `agentboard daemon start|stop|status`
- `templates/platform/scripts/hooks/event-logger.sh` — daemon HTTP path (fallback preserved)
- `templates/platform/scripts/session-track.sh` — auto-start/stop daemon around session
- `templates/platform/scripts/codex-ab` / `gemini-ab` — session-track auto-start
- `tests/unit/daemon_test.sh` — HTTP endpoints + concurrent write safety

### Phase 2 — File lock queue (DONE ✅)
- `bin/agentboard-daemon.js` — add `POST /lock`, `DELETE /lock`, `GET /locks` endpoints
- `templates/platform/scripts/hooks/pre-tool-use-lock.sh` — Claude PreToolUse hook: blocks Write/Edit/MultiEdit on locked files, polls until granted (hard enforcement)
- `templates/platform/scripts/hooks/post-tool-use-unlock.sh` — Claude PostToolUse hook: releases lock after write completes
- `lib/agentboard/commands/lock.sh` — `agentboard lock acquire|release|list` (Codex honor-system path)
- `bin/agentboard` — register lock subcommand
- `templates/root/.claude/settings.json` — register PreToolUse + PostToolUse lock hooks
- `lib/agentboard/commands/update.sh` — add new hooks to upsert list
- `tests/unit/lock_test.sh` — acquire/release/queue/timeout/list tests

**Out of scope:**
- No work-stealing or task assignment (who owns which module)
- No persistent daemon (session-scoped only)
- No authentication / encryption (local loopback only)
- No Codex hard enforcement (platform gap — Codex has no PreToolUse API)

## Done criteria

### Phase 1 ✅
- [x] `agentboard daemon start` launches daemon, writes port file, prints PID
- [x] `agentboard daemon stop` kills daemon, cleans up port file
- [x] `agentboard daemon status` shows running/stopped + event count
- [x] `POST /event` appends enriched event to events.jsonl; returns 204
- [x] `GET /events` returns filtered JSON array (since, stream, tool, limit params)
- [x] `GET /health` returns pid/uptime/events JSON
- [x] event-logger.sh tries daemon first, falls back to direct JSONL on failure
- [x] session-track.sh auto-starts daemon before file poller, stops on exit
- [x] Two parallel writes don't corrupt events.jsonl (concurrent safety test)
- [x] All unit tests pass

### Phase 2
- [x] `POST /lock {file, provider, session_id}` → 200 (acquired) or 202 (queued)
- [x] `DELETE /lock {file, provider, session_id}` → releases lock, grants to next in queue
- [x] `GET /locks` → JSON array of current locks + queues
- [x] Lock state persisted to `.platform/.file-locks.json` (survives daemon restart)
- [x] `agentboard lock acquire <file>` → acquires or blocks until granted (30s timeout)
- [x] `agentboard lock release <file>` → releases
- [x] `agentboard lock list` → pretty-prints current locks + queue
- [x] PreToolUse hook blocks Claude's Write/Edit/MultiEdit on locked files
- [x] PostToolUse hook releases lock after tool completes
- [x] Lock auto-expires after 5 min (prevents deadlock if agent crashes mid-edit)
- [x] Codex-ab / gemini-ab inject lock instructions into session context
- [x] All unit tests pass
- [x] `.platform/memory/log.md` appended
- [x] decisions.md updated

## Key decisions

2026-04-18 — Node built-ins only, zero npm — agentboard CLI has no required runtime deps
2026-04-18 — Dynamic port (OS-assigned), written to .platform/.daemon-port — no port conflicts across projects
2026-04-18 — Daemon is session-scoped — started by wrapper, not a system daemon
2026-04-18 — File lock enforcement asymmetry: Claude = hard (PreToolUse hook blocks tool call); Codex = honor system (system prompt convention + CLI). Platform gap — Codex has no PreToolUse API.
2026-04-18 — Lock auto-expiry at 5 min — prevents deadlock if agent crashes without releasing. Configurable via .platform/config if needed later.
2026-04-18 — Lock granularity is normalized file path (relative to repo root) — avoids duplicate locks from absolute vs relative path differences
2026-04-18 — Lock ownership is keyed by `session_id`, not provider name — same-provider concurrency is expected, so provider-only identity is unsafe

## Resume state

- **Last updated:** 2026-04-18 — by claude-code
- **What just happened:** Fixed session-safe lock ownership, added wrapper lock guidance, covered same-provider queueing plus auto-expiry in tests, and reconciled the stream state to match the implementation.
- **Current focus:** Awaiting user verification and closure decision.
- **Next action:** Present evidence of completion to the user and ask whether to close the stream.
- **Blockers:** none

## Progress log

2026-04-18 09:00 — Stream created. Phase 1 scope defined.
2026-04-18 11:45 — Phase 1 complete. Daemon + event serialization shipped, 10 tests passing.
2026-04-18 12:00 — Stream updated with Phase 2 scope (file lock queue). Executing.
2026-04-18 23:10 — Session-scoped lock ownership, wrapper guidance, and missing Phase 2 regressions landed; focused daemon, lock, and stream-bookkeeping suites are green.

## Open questions

_none_
