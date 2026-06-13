---
domain_id: dom-agent-roles-skills
slug: agent-roles-skills
status: active
repo_ids: [repo-primary]
related_domain_slugs: [templates, commands]
created_at: 2026-06-13
updated_at: 2026-06-13
---

# agent-roles-skills

## What this domain does

This domain defines how Agentboard ships reusable agent skills and role profiles across Claude Code, Codex CLI, and Gemini CLI. It covers the source templates, installed runtime copies, root-entry activation instructions, role routing, and tests that keep the pack discoverable and provider-compatible.

## Backend / source of truth

- Shipped skills live under `templates/skills/<skill>/SKILL.md` and are synced into project-local skill directories by `agentboard init` and `agentboard update`.
- Shipped roles live under `templates/platform/roles/`, with `INDEX.md` as the routing table and one `<slug>.md` file per role.
- Runtime installed copies may exist under `.claude/skills/`, `.agents/skills/`, `.codex/skills/`, and `.platform/roles/` for the current project.
- `lib/agentboard/commands/init.sh` installs initial skills and roles; `lib/agentboard/commands/update.sh` refreshes shipped protocol content.
- `lib/agentboard/commands/role.sh` exposes `agentboard role list` and `agentboard role show <slug>`.

## Frontend / clients

- Root entry templates (`templates/root/CLAUDE.md.template`, `templates/root/AGENTS.md.template`, `templates/root/GEMINI.md.template`, and hub variants) tell agents how to discover and activate roles and skills.
- `.platform/agents/skill-labels.md` and its template define label stacking conventions for `[role:<slug>]` plus `[ab-*]`.
- README and CHEATSHEET document user-facing role and skill workflows.

## API contract locked

- Role files must have complete frontmatter, a `label: "[role:<slug>]"`, required sections, and stack-agnostic content.
- `templates/platform/roles/INDEX.md` must include every shipped role and remain small enough to load at session start.
- Skills must use valid `SKILL.md` frontmatter with `name` and `description`; trigger conditions belong in the description.
- Shipped skills are replaced by `agentboard update`; project-specific content should not live inside shipped skill files.
- Any new shipped role or skill must be reflected in the appropriate root-entry templates, activation docs, README/CHEATSHEET when user-facing, and tests.

## Key files

- `templates/skills/`
- `templates/platform/roles/`
- `templates/root/CLAUDE.md.template`
- `templates/root/CLAUDE.md.hub.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `templates/platform/ACTIVATE.md`
- `templates/platform/ACTIVATE-HUB.md`
- `templates/platform/agents/skill-labels.md`
- `lib/agentboard/commands/init.sh`
- `lib/agentboard/commands/update.sh`
- `lib/agentboard/commands/role.sh`
- `tests/unit/roles_pack_test.sh`
- `tests/unit/commands_role_test.sh`
- `tests/unit/workflow_contract_test.sh`

## Decisions locked

- Roles define who is working and what done looks like; `ab-*` skills define the process or workflow used by that role.
- Role activation must happen before skill invocation in root-entry instructions.
- Shipped role and skill content must stay provider-neutral unless a file is explicitly provider-specific.
- New cleanup/refactor behavior should be implemented as a reusable skill plus an appropriate role, not as ad hoc root-entry prose alone.
