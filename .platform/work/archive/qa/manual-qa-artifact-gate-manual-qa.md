---
stream_slug: manual-qa-artifact-gate
artifact_type: manual-qa
status: passed
created_at: 2026-06-15
updated_at: 2026-06-15
---

# Manual QA Artifact — manual-qa-artifact-gate

## Execution Summary

- Verdict: `PASS`
- Tester: Codex
- Date: 2026-06-15
- Evidence:
  - `bash tests/unit/workflow_contract_test.sh` → passed
  - `bash tests/unit/entry_templates_handoff_test.sh` → passed
  - `bash tests/unit/qa_self_heal_contract_test.sh` → passed
  - `bash tests/unit.sh` → `PASS: unit (49 files, 391 tests)`
  - `git diff --check` → passed
- Remaining risk: no UI/browser surface was exercised because this stream
  changes CLI workflow, templates, skills, roles, and shell contract tests.

## Scope

Validate that Agentboard now treats Manual QA as a durable markdown artifact gate
before commit, push, merge, release, or stream closure when human or app-driving
verification matters.

## Environment

- Repo: `agentboard`
- Worktree: `/private/tmp/agentboard-manual-qa-artifact-gate`
- Branch: `feature/manual-qa-artifact-gate`
- Base: `origin/main`
- Runtime: shell-only CLI/docs project; no localhost service required
- Tester: human QA, Codex/Claude/Gemini agent, or Maestro-style app-driving
  agent reviewing the workflow files and running shell checks

## Test Data

- Active stream: `.platform/work/manual-qa-artifact-gate.md`
- Manual QA artifact under test:
  `.platform/work/qa/manual-qa-artifact-gate-manual-qa.md`
- Workflow sources:
  - `.platform/workflow.md`
  - `templates/platform/workflow.md`
- Provider entry files:
  - `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
  - `templates/root/AGENTS.md.template`
  - `templates/root/CLAUDE.md.template`
  - `templates/root/GEMINI.md.template`

## Safety Limits

- Do not delete active or archived QA artifacts.
- Do not archive the stream unless `closure_approved: true` is present and the
  owner has approved closure.
- Do not commit/push/release until the focused contract tests pass.
- Do not run destructive git commands such as force push or hard reset.

## Happy Path

### QA-001 — Workflow gate exists

1. Open `templates/platform/workflow.md`.
   Expected: The commit gate heading mentions `git commit`, `git push`, merge,
   release, and stream closure.
2. In the commit gate table, locate `Manual QA artifact clear`.
   Expected: The requirement names `.platform/work/qa/<stream-slug>-manual-qa.md`
   and the fallback `Manual QA: not required — <specific reason>`.
3. Open `.platform/workflow.md`.
   Expected: The same gate exists in the live dogfood copy.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-002 — Manual QA artifact format is complete

1. Open `templates/platform/workflow.md`.
   Expected: The section `Manual QA artifact — required when human verification
   matters` exists.
2. Review the artifact template.
   Expected: It includes scope, environment, test data, safety limits, exact
   action steps, expected results, bug repro/regression, edge cases,
   browser/device checks, accessibility checks, evidence, Maestro/automation
   notes, and signoff.
3. Open `.platform/workflow.md`.
   Expected: The live copy contains the same required fields.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-003 — Provider entry files inherit the rule

1. Open `AGENTS.md`.
   Expected: It has `Manual QA artifact rule` and requires creating
   `.platform/work/qa/<stream-slug>-manual-qa.md` before commit, push, merge,
   release, or stream closure.
2. Open `CLAUDE.md` and `GEMINI.md`.
   Expected: Both contain the same durable QA artifact rule.
3. Open the three root templates under `templates/root/`.
   Expected: All three templates contain the same rule for new projects.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-004 — QA skills produce a file, not only chat text

1. Open `templates/skills/ab-workflow/SKILL.md`.
   Expected: Stage 6 says to create/update
   `.platform/work/qa/<stream-slug>-manual-qa.md` and reports the artifact path.
2. Open `templates/skills/ab-qa/SKILL.md`.
   Expected: The skill has `Write` and `Edit` tools and tells QA to create a
   durable tester-facing Manual QA artifact.
3. Open `templates/skills/ab-qa-self-heal/SKILL.md`.
   Expected: The report template contains `## Manual QA Artifact`, the default
   path, and Maestro/human rerun guidance.
4. Repeat the check in `.agents/skills/` and `.claude/skills/`.
   Expected: Installed live skills match the template rule.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-005 — QA roles own the deliverable

1. Open `templates/platform/roles/qa-engineer.md` and
   `.platform/roles/qa-engineer.md`.
   Expected: Deliverables include a Manual QA artifact and a preserve/archive
   history rule.
2. Open `templates/platform/roles/qa-automation-engineer.md` and
   `.platform/roles/qa-automation-engineer.md`.
   Expected: Process and deliverables include writing the artifact with
   human/Maestro executable steps.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-006 — Contract tests enforce the workflow

1. Run `tests/unit/workflow_contract_test.sh`.
   Expected: The test exits 0 and checks the Manual QA artifact gate.
2. Run `tests/unit/entry_templates_handoff_test.sh`.
   Expected: The test exits 0 and confirms provider entries reference the
   durable QA artifact path and archive path.
3. Run `tests/unit/qa_self_heal_contract_test.sh`.
   Expected: The test exits 0 and confirms QA self-heal outputs the Manual QA
   artifact.

Result: `PASS / FAIL / BLOCKED`
Evidence:

## Bug Repro / Regression

### QA-101 — Old chat-only QA plan is no longer enough

1. Search the workflow and provider templates for the old requirement:
   `Manual QA plan rule`.
   Expected: No provider template relies on the old chat-only wording.
2. Search QA skills for `tester-facing manual plan`.
   Expected: The old phrase is gone or replaced with durable Manual QA artifact
   wording.
3. Confirm `Manual QA: not required — <specific reason>` remains available.
   Expected: The explicit no-QA escape hatch still exists for work where manual
   verification is genuinely irrelevant.

Result: `PASS / FAIL / BLOCKED`
Evidence:

## Edge Cases

### QA-201 — Non-UI/backend work can opt out with a reason

1. Open `templates/platform/workflow.md`.
   Expected: It allows `Manual QA: not required — <specific reason>`.
2. Confirm the rule requires this reason in the stream file, not only chat.
   Expected: The stream-file recording requirement is present.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-202 — Closed streams preserve QA evidence

1. Open `templates/platform/workflow.md`.
   Expected: Stream closure says to move QA artifacts to
   `.platform/work/archive/qa/`.
2. Confirm it says not to delete Manual QA artifacts.
   Expected: QA history is preserved for future regression reference.

Result: `PASS / FAIL / BLOCKED`
Evidence:

### QA-203 — Agentboard dogfoods the artifact

1. Confirm this file exists:
   `.platform/work/qa/manual-qa-artifact-gate-manual-qa.md`.
   Expected: The stream has its own Manual QA artifact before commit/release.
2. Confirm the active stream references the QA artifact.
   Expected: `.platform/work/manual-qa-artifact-gate.md` records the artifact
   path or the done criteria mention the artifact gate.

Result: `PASS / FAIL / BLOCKED`
Evidence:

## Browser / Device Checks

Not required for this stream because the change is CLI/process documentation and
contract tests, not a rendered web or mobile surface.

## Accessibility Checks

Not required for this stream because there is no UI surface. For future UI
streams, the required QA artifact must include keyboard, focus, labels, and
contrast checks when relevant.

## Evidence To Capture

- Output from:
  - `tests/unit/workflow_contract_test.sh`
  - `tests/unit/entry_templates_handoff_test.sh`
  - `tests/unit/qa_self_heal_contract_test.sh`
  - full relevant unit suite if run
- `git diff --check`
- `git status --short --branch`
- Optional screenshots only if a rendered UI is involved in a future stream

## Maestro / Automation Notes

- No Maestro runtime is needed for this CLI workflow stream.
- A Maestro-style agent can still execute this artifact by opening the named
  files, checking the specified strings, running the shell tests, and recording
  pass/fail results above.
- Future app streams should include stable selectors, screen names, flow caps,
  forbidden destructive actions, API/rate limits, and screenshot/report paths.

## Signoff

- Tester: Codex
- Date: 2026-06-15
- Verdict: `PASS`
- Remaining risk: no browser/device QA was needed for this CLI workflow stream.
