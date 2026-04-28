---
domain_id: dom-new-stream-workflow
slug: new-stream-workflow
status: active
repo_ids: [repo-primary]
related_domain_slugs: [templates, commands, framework-audit]
created_at: 2026-04-27
updated_at: 2026-04-27
---

# new-stream-workflow

## What this domain does

Defines the cross-provider intake contract for starting a new Agentboard workstream. It keeps Codex, Claude, Gemini, and future agents aligned on when a user request becomes a stream and what research, planning, approval, execution, and verification steps must happen before implementation.

## Backend / source of truth

- `.platform/workflow.md` is the canonical workflow spec agents must follow inside activated projects.
- `templates/platform/workflow.md` is the shipped copy new projects inherit.
- `templates/skills/ab-workflow/SKILL.md`, `templates/skills/ab-research/SKILL.md`, and `templates/skills/ab-triage/SKILL.md` operationalize the workflow.
- `templates/platform/work/TEMPLATE.md` defines the stream file fields that preserve resumable state.

## Frontend / clients

- Root provider entries (`templates/root/CLAUDE.md.template`, `templates/root/AGENTS.md.template`, `templates/root/GEMINI.md.template`) tell each LLM what to do when a new task appears.
- In-repo `.platform/work/*` files are the human-readable work queue and handoff surface.
- Provider-specific wrappers and hooks can only assist; the workflow must remain understandable from docs alone.

## API contract locked

- A non-trivial untracked task must be registered before research, planning, or code.
- New streams must follow a research-first workflow before implementation unless the task is explicitly trivial.
- Plans must include phases, risks, complexity, alternatives, and human approval gates.
- Implementation must stay traceable to the approved plan and preserve human-in-the-loop validation.

## Key files

- `.platform/workflow.md`
- `templates/platform/workflow.md`
- `templates/platform/work/TEMPLATE.md`
- `templates/root/CLAUDE.md.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `templates/skills/ab-workflow/SKILL.md`
- `templates/skills/ab-research/SKILL.md`
- `templates/skills/ab-triage/SKILL.md`

## Decisions locked

- The canonical rule belongs in `.platform/workflow.md` and its template copy; provider entry files should point to the same contract instead of redefining it differently.
- Research output stays in chat unless it becomes reusable project knowledge; the stream file records state and decisions, not long-form research notes.
- Human approval is required before implementation on medium+ new streams and before closing any stream.
