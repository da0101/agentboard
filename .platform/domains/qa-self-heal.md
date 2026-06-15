---
domain_id: dom-qa-self-heal
slug: qa-self-heal
status: active
repo_ids: [repo-primary]
related_domain_slugs: [agent-roles-skills, templates]
created_at: 2026-06-14
updated_at: 2026-06-14
---

# qa-self-heal

## What this domain does

This domain defines how Agentboard should guide agents through automated app-driving QA loops: explore the app, stress limits, collect reports, feed findings back into implementation, and repair issues until further automated fixing is no longer sensible. It covers external QA drivers such as Maestro, cross-provider skill/role routing, report ingestion, safety boundaries, and verification contracts.

## Backend / source of truth

- Shipped QA/self-heal guidance should live in `templates/skills/` and `templates/platform/roles/` when it needs to be reused across projects.
- Root entry templates and activation docs must tell Claude, Codex, and Gemini how to invoke the capability without provider-specific drift.
- Workflow rules in `templates/platform/workflow.md` and `.platform/workflow.md` define when agents may fix findings, when they must stop, and how evidence gets reported.
- CLI/init/update behavior may need to sync any new skill/role content into `.claude/skills/`, `.agents/skills/`, `.codex/skills/`, and `.platform/roles/`.

## Frontend / clients

- Target apps may be web, mobile, desktop, or API-backed UI flows; Agentboard should provide a generic protocol that lets the agent adapt to the project’s actual test runner and app driver.
- Maestro is one concrete driver for app navigation; Browser/Playwright or API-level tools may complement it when the app surface is not mobile-only.
- Reports and execution journals must be readable by the next agent: every
  interactive step taken, observations, failures, successful paths,
  reproduction steps, logs, screenshots/videos if available, suspected layer,
  fix attempts, human requests/blockers, retests, and stopping rationale.

## API contract locked

- The QA self-heal loop must be bounded: scan/explore, generate scenarios, run, classify, fix only approved/safe classes, verify, and stop on diminishing returns or unsafe scope.
- Agents must not perform destructive load testing against production or third-party services without explicit user approval.
- Rate-limit/backend/API stress must use configured local/staging environments, synthetic data, and project-defined safety caps.
- Any new shipped role or skill must remain provider-neutral and must be installed through the existing template/update pipeline.
- The workflow must preserve existing human approval gates for new streams, commits, releases, and stream closure.
- LLM-driven interactive QA must produce a chronological execution journal, not
  only a final summary. The journal records what happened from the agent's
  perspective so QA evidence, odd behavior, and successful flows survive
  handoff.

## Key files

- `templates/skills/`
- `templates/platform/roles/`
- `templates/platform/workflow.md`
- `templates/root/CLAUDE.md.template`
- `templates/root/CLAUDE.md.hub.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `templates/platform/ACTIVATE.md`
- `templates/platform/ACTIVATE-HUB.md`
- `lib/agentboard/commands/init.sh`
- `lib/agentboard/commands/update.sh`
- `tests/unit/roles_pack_test.sh`
- `tests/unit/workflow_contract_test.sh`

## Decisions locked

- QA self-healing is a controlled loop, not permission for open-ended rewrites.
- External app drivers such as Maestro are optional project capabilities; Agentboard should detect/document how to use them rather than hard-require them for every project.
- Reports and evidence are first-class outputs because the next agent must understand what was tested, fixed, skipped, or stopped.
- Execution journals are first-class outputs for Maestro/browser/app-driving QA
  because they expose the exact QA pipeline behavior, including successful
  tests and failed/fixed paths.
