---
domain_id: dom-product-engineering-mindset
slug: product-engineering-mindset
status: active
repo_ids: [repo-primary]
related_domain_slugs: [agent-roles-skills, templates, new-stream-workflow]
created_at: 2026-06-14
updated_at: 2026-06-14
---

# product-engineering-mindset

## What this domain does

This domain defines the mindset Agentboard should ask PM and engineering agents to bring to product work: ambitious, future-facing, craft-driven, and benchmarked against leading technology products while still grounded in the user, constraints, and ship-quality execution.

## Source of truth

- Role profiles under `templates/platform/roles/` define how PMs and engineers frame work.
- Workflow and activation templates define process rules that apply across providers.
- Root entry templates (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) are how this mindset reaches Claude, Codex, and Gemini after `ab init`.
- Durable decisions in `.platform/memory/decisions.md` record stable process expectations.

## API contract locked

- The mindset should push agents to think beyond basic requirements: user delight, leverage, defensibility, craft, speed, scalability, and future product direction.
- It must not become hype-driven scope creep. Agents still ship the smallest coherent slice, state tradeoffs, respect approval gates, and avoid inventing unapproved features.
- PMs should frame user value, product differentiation, and success criteria.
- Engineers should translate that ambition into robust, maintainable, testable implementation.
- The rule must be provider-neutral and live in shipped templates, not only the local Agentboard repo.

## Key files

- `templates/platform/workflow.md`
- `.platform/workflow.md`
- `templates/platform/roles/INDEX.md`
- `.platform/roles/INDEX.md`
- `templates/platform/roles/product-manager.md`
- `templates/platform/roles/feature-builder.md`
- `templates/platform/roles/startup-mvp.md`
- `templates/root/CLAUDE.md.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `.platform/memory/decisions.md`
