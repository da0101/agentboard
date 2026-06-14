# Feature Brief — agentboard

> Read this first — every session, every agent (Claude, Codex, Gemini).
> 30-second orientation: what we're building, why, and where we stand.
> Replace entirely when the active feature changes. Keep ≤60 lines.

**Feature:** qa-self-heal-maestro
**Status:** awaiting-verification
**Stream file:** `.platform/work/qa-self-heal-maestro.md`

---

## What we're building

We are adding an Agentboard QA self-heal capability: reusable guidance so Claude Code, Codex CLI, and Gemini CLI can drive an app with tools such as Maestro, explore flows, stress practical limits, ingest reports, and fix safe findings in a bounded loop.

## Why

Users want agents to perform deep app QA beyond static tests: click through UI, drill into edge cases, exercise backend/API/rate-limit boundaries, collect evidence, feed findings back into the coding loop, and stop when the remaining work is unsafe or no longer worth automating.

## What done looks like

- A research-backed plan is approved before implementation.
- The workflow has explicit safety bounds for local/staging vs production and third-party calls.
- Any new skill/role/template content is shipped through existing Agentboard init/update paths.
- Tests verify role/skill/template integrity and any changed install/update behavior.

## Architecture decisions locked

- QA self-heal must be bounded and evidence-driven, not an open-ended rewrite loop.
- External tools such as Maestro are optional project capabilities, not mandatory dependencies for every Agentboard install.
- Existing approval gates for new streams, commits, releases, and stream closure remain intact.

## Current state

Implementation is complete in `/private/tmp/agentboard-qa-self-heal` on `feature/qa-self-heal-maestro`; awaiting user review/sign-off. Focused QA/role/install/update tests pass. Full aggregate `bash tests/unit.sh` reproduces an existing daemon-start race in 3 daemon-dependent files, while those files pass individually.

See `work/ACTIVE.md` for stream status.

## Relevant context

> Only load files relevant to the next task. Do not auto-load archived streams.

**Primary stream:** `.platform/work/qa-self-heal-maestro.md`
**Domain:** `.platform/domains/qa-self-heal.md`
**Do not load:** unrelated archived stream files
**Never load:** `work/archive/*`

## Key files

- `.platform/work/ACTIVE.md`
- `.platform/work/qa-self-heal-maestro.md`
- `.platform/domains/qa-self-heal.md`
- `templates/skills/`
- `templates/platform/roles/`
- `templates/platform/workflow.md`
- `templates/root/AGENTS.md.template`
- `templates/root/CLAUDE.md.template`
- `templates/root/GEMINI.md.template`
- `.platform/memory/log.md`
