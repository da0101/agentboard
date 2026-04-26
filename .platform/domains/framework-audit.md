---
domain_id: dom-framework-audit
slug: framework-audit
status: active
repo_ids: [repo-primary]
related_domain_slugs: [core, commands, templates, orchestration, usage-intelligence]
created_at: 2026-04-18
updated_at: 2026-04-18
---

# framework-audit

## What this domain does

Defines the audit surface for Agentboard as a whole: CLI entrypoints, command implementations, template payloads, workflow rules, memory files, hooks, daemon orchestration, and the shell test harness that verifies them.

## Source of truth

This concern spans one repo but multiple layers. A credible audit has to inspect both the shipped runtime and the project-process layer under `.platform/`, because Agentboard's product claim is not just "bash commands run" but "multiple agents can coordinate and resume work with shared context."

## Key files

- `bin/agentboard` — CLI entrypoint and dispatcher
- `lib/agentboard/core/*.sh` — shared parsing, rendering, state, bootstrap helpers
- `lib/agentboard/commands/*.sh` — user-facing behavior
- `bin/agentboard-daemon.js` — optional event-serialization daemon
- `templates/platform/**` — generated hooks, memory pack, and entry files users actually inherit
- `.platform/workflow.md` — operating model the framework expects agents to follow
- `.platform/work/*.md` — live stream state that enables handoff/resume
- `.platform/memory/*.md` — persistent institutional memory layer
- `tests/unit/*.sh`, `tests/integration.sh`, `tests/helpers.sh` — regression safety net

## Audit questions

- Does the framework preserve enough state for one LLM to hand work to another without re-explaining the task?
- Is automation reducing operator burden, or just adding ceremony around manual process?
- Are the workflow rules enforceable, or mostly aspirational?
- Is the implementation robust enough for everyday use on real repos and long sessions?
- Are tests broad enough to justify confidence in changes to commands, templates, and orchestration?

## Failure modes to watch

- Process quality depends on humans remembering rituals that are only partially enforced
- Multiple files claim to be the source of truth and drift apart
- Shell implementation complexity exceeds the safety provided by the test harness
- Context-sharing succeeds for disciplined users but collapses under partial adoption
