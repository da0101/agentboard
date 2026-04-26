---
domain_id: dom-usage-intelligence
slug: usage-intelligence
status: active
repo_ids: [repo-primary]
related_domain_slugs: [commands, core]
created_at: 2026-04-17
updated_at: 2026-04-17
---

# usage-intelligence

## What this domain does

Tracks token consumption across provider sessions, converts raw usage segments
into stream-level insights, and feeds those insights back into the project via
briefing and learning files so future sessions spend fewer tokens.

## Cross-layer touch-points

| Layer | Files | Responsibility |
|---|---|---|
| CLI entry | `lib/agentboard/commands/help.sh` | Documents usage / checkpoint / learn surfaces |
| Session logging | `lib/agentboard/commands/checkpoint.sh` | Captures usage automatically at stream boundaries |
| Usage store | `lib/agentboard/commands/usage.sh` | SQLite schema, segment logging, summaries, optimization, learning |
| Session briefing | `lib/agentboard/commands/brief.sh` | Surfaces learned patterns and spend hotspots at session start |
| Durable memory | `.platform/memory/learnings.md`, `.platform/memory/BACKLOG.md` | Stores applied learnings and deferred observability work |
| Tests | `tests/unit/checkpoint_usage_test.sh`, `tests/unit/commands_usage_test.sh` | Locks usage math, reporting, and learning behavior |

## Contracts that matter

- Usage rows must be attributable by provider, model, stream, repo, and task type.
- `checkpoint` must be able to log session totals without double-counting.
- Learning output must be based on repeated patterns, not one-off spikes.
- Briefing should summarize where tokens went without requiring manual SQLite queries.
- The system should help explain waste sources such as conversational drift, model overkill, and too-late checkpointing.

## Known risks

- If `checkpoint` stores only vague labels like `normal` / `heavy`, learnings stay too coarse to explain waste.
- If segments are logged too infrequently, large sessions collapse into one opaque row and root-cause analysis becomes impossible.
- If learning thresholds are too strict, obvious waste never gets promoted into actionable guidance.
