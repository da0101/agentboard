---
domain_id: dom-manual-qa-artifacts
slug: manual-qa-artifacts
status: active
repo_ids: [repo-primary]
related_domain_slugs: [new-stream-workflow, templates, qa-self-heal]
created_at: 2026-06-15
updated_at: 2026-06-15
---

# manual-qa-artifacts

## What this domain does

Defines the required manual QA artifact workflow for Agentboard streams. A
manual QA plan in chat is no longer enough for shippable work that needs human
or app-driving verification: agents must create a durable markdown QA manual
with explicit step-by-step coverage before commit, push, release, or stream
closure. When an LLM drives an app with Maestro, browser automation, or another
interactive tool, the workflow must also capture a QA execution journal: what
the agent actually did, saw, fixed, retested, skipped, and escalated.

## Source of truth

- `.platform/workflow.md` is the canonical process gate in an activated repo.
- `templates/platform/workflow.md` is the shipped copy new projects inherit.
- Root entry templates (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) expose the gate
  to all providers.
- QA skills and roles operationalize the artifact for human testers and
  Maestro/app-driving agents.
- Stream files record the artifact path and verification status.
- Closed stream QA artifacts are archived under `.platform/work/archive/qa/`.
- QA execution journals are stored beside the manual QA artifact and archived
  with the same retention rules.

## API contract locked

- Manual QA is a hard gate when a feature, bugfix, implementation, or behavior
  change needs human/app-driving verification.
- The agent must create a markdown QA artifact, not only write QA steps in chat.
- The artifact must be detailed enough for a human QA tester or Maestro-style
  agent to execute: prerequisites, environment, test data, navigation, click
  targets, inputs, expected results, regressions, edge cases, accessibility
  checks when relevant, evidence to capture, and pass/fail signoff.
- Commit, push, release, and stream closure are blocked until the manual QA
  artifact exists or the agent explicitly records why manual QA is not required.
- Manual QA artifacts are never deleted during closure. Active artifacts live
  under `.platform/work/qa/`; closed stream artifacts move to
  `.platform/work/archive/qa/` for regression reference.
- For multi-repo or app-driving work, the artifact must identify the target app,
  local/staging URL, accounts/fixtures, and any safety caps.
- App-driving QA must include an execution journal with chronological steps,
  observations, bugs/errors, diagnosis, fixes, human requests/blockers,
  retests, pass/fail outcomes, and evidence links. Successful tests are
  documented too.
- The gate must be provider-neutral and live in shipped templates, not only the
  local Agentboard repo.

## Key files

- `.platform/workflow.md`
- `templates/platform/workflow.md`
- `templates/root/CLAUDE.md.template`
- `templates/root/AGENTS.md.template`
- `templates/root/GEMINI.md.template`
- `templates/skills/ab-qa/SKILL.md`
- `templates/skills/ab-qa-self-heal/SKILL.md`
- `.claude/skills/ab-qa/SKILL.md`
- `.agents/skills/ab-qa/SKILL.md`
- `.platform/roles/qa-engineer.md`
- `.platform/roles/qa-automation-engineer.md`
- `.platform/work/qa/<stream-slug>-manual-qa.md`
- `.platform/work/qa/<stream-slug>-execution-journal.md`
- `.platform/work/archive/qa/<stream-slug>-manual-qa.md`
- `.platform/work/archive/qa/<stream-slug>-execution-journal.md`
- `tests/unit/workflow_contract_test.sh`
