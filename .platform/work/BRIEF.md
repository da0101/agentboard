# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** code-cleanup-skill-role
**Status:** awaiting-verification
**Stream file:** `.platform/work/code-cleanup-skill-role.md`

---

## What we're building

We are adding an Agentboard cleanup capability: a reusable skill plus the right role/routing so Claude Code, Codex CLI, and Gemini CLI can respond consistently when asked to clean up a whole codebase or a targeted path/feature/file/folder.

## Why

Cleanup requests should trigger a disciplined scan-first workflow for duplication, dead code, oversized files, noisy comments, avoidable complexity, performance opportunities, and general housekeeping without unsafe broad rewrites.

## What done looks like

- A research-backed plan is approved before implementation.
- The skill and role/routing are shipped through the same template/update paths as the existing role and skill packs.
- Tests verify role/skill pack integrity and any install/update behavior touched.
- The stream records verification evidence and durable memory updates.

## Architecture decisions locked

- Roles define who is working and what done looks like; `ab-*` skills define process stages and workflows.
- Shipped skills live under `templates/skills/` and sync into provider-specific skill dirs.
- Shipped roles live under `templates/platform/roles/`, with `INDEX.md` as the routing source.

## Current state

Implementation is verified in `/Users/danilulmashev/Documents/GitHub/agentboard-code-cleanup-skill-role` on `feature/code-cleanup-skill-role`; awaiting user review/sign-off.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load files relevant to the next task. Do not auto-load archived streams.

**Primary stream:** `.platform/work/code-cleanup-skill-role.md`
**Domain:** `.platform/domains/agent-roles-skills.md`
**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `.platform/work/ACTIVE.md`
- `.platform/work/code-cleanup-skill-role.md`
- `.platform/domains/agent-roles-skills.md`
- `templates/skills/`
- `templates/platform/roles/`
- `lib/agentboard/commands/init.sh`
- `lib/agentboard/commands/update.sh`
- `.platform/memory/log.md`
