# agentboard HUD status schemas

This directory contains versioned JSON Schema contracts for agentboard's live session state.

## agentboard.hud-status.v1.json

Defines the portable data format any HUD tool (VS Code extension, terminal dashboard, web UI) reads to render agentboard status without coupling to agentboard internals.

**Eight top-level sections:** `context` (model/repo/branch/pressure), `tool_calls` (recent activity + pending count), `active_agents` (running subagents), `todos` (in-progress tasks + counts), `checks` (CI + local test health), `cost` (session USD + token accounting), `risk` (dirty worktree, conflicts, manual-review flags), and `queue` (open PRs, merge queue depth, issue count).

**All fields are optional.** A consumer must treat any missing field as "unavailable" and never infer false positives. This allows partial emitters (e.g. a tool that only knows CI status) to emit a valid document.

### Emitting a status document

Produce a JSON object that validates against this schema and write it to a well-known path, e.g. `.platform/hud-status.json`. Agentboard itself will write this file during active sessions; third-party tools may write their own fields and merge.

### Consuming a status document

Read `.platform/hud-status.json`, validate the top-level `$schema` field, then render only the sections present. If a section is absent, show a greyed-out "unavailable" indicator rather than zero or false.

### Versioning

The filename encodes the schema version (`v1`). Breaking changes produce a new file (`v2`); additive changes are made in place because all fields are optional.
