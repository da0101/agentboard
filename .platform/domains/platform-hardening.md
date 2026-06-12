---
domain_id: dom-platform-hardening
slug: platform-hardening
status: active
repo_ids: [repo-primary]
related_domain_slugs: [core, commands, templates, orchestration, usage-intelligence]
created_at: 2026-04-18
updated_at: 2026-04-18
---

# platform-hardening

## What this domain does

Tracks the cross-cutting hardening work needed to make Agentboard's context-sharing and automation claims more trustworthy in real multi-provider use.

## Scope of this hardening pass

- Make stream identity explicit in event capture instead of inferring it from the first active stream.
- Separate durable project-truth files from transient runtime artifacts and keep the transient state out of normal commits.
- Unify bootstrap/wrapper/session code around the same canonical resume-state parser.
- Tighten tests around multi-stream behavior and environment fallbacks.

## Cross-layer touch-points

- `templates/platform/scripts/hooks/event-logger.sh` — event tagging and payload shaping
- `templates/platform/scripts/session-track.sh` — session lifecycle and daemon bootstrap
- `templates/platform/scripts/codex-ab`, `templates/platform/scripts/gemini-ab` — provider wrappers and stream export
- `templates/platform/scripts/hooks/platform-bootstrap.sh` — session-start advisory summary
- `bin/agentboard-daemon.js` — runtime files and lock persistence
- `lib/agentboard/core/project_state.sh` — canonical resume-state parsing
- `lib/agentboard/commands/init.sh`, `update.sh`, `doctor.sh` — project bootstrap, upgrades, validation
- `tests/unit/*.sh`, `tests/integration.sh` — regression coverage for hardening

## Invariants

- Event records must be attributable to the correct stream even when multiple streams are active.
- Durable context files remain human-readable and version-worthy; runtime artifacts do not pollute normal commits.
- Session-start and resume helpers must read one canonical representation of next action/resume state.
- Test outcomes must not depend on ambient provider env vars in the parent shell.

## Failure modes to prevent

- Cross-provider activity attributed to the wrong stream
- Sensitive or noisy runtime artifacts ending up in git history
- Wrapper/bootstrap code showing stale or empty next actions because it reads old sections
- Green local tests hiding failures that appear in a shell with provider env vars set
