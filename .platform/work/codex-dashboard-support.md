---
stream_id: stream-codex-dashboard-support
slug: codex-dashboard-support
type: feature
status: planned
agent_owner: claude
domain_slugs: [vscode-extension]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/codex-dashboard-support
created_at: 2026-06-20
updated_at: 2026-06-20
closure_approved: false
---

# codex-dashboard-support

Apply the same real-time dashboard treatment to Codex sessions that was built for Claude Code in the 2.1.0 vscode extension release.

## Context

The 2.1.0 release shipped a full live dashboard for Claude Code sessions:
- Session columns with cost, context, branch, last-updated
- WORKFLOW section (collapsible, per-agent status with model/running/done)
- SUB-AGENTS section with staleness detection
- ACTIVITY feed with git diff stats (+N/-N), collapsible, inner scroll
- CATALOG tab with skill/role expand + "used by" session badges
- Status driven by `~/.agentboard/sessions/<id>.json` (written by status-bridge.js hook)
- Events driven by `.platform/events.jsonl` (written by event-logger.sh PostToolUse hook)

Codex needs the same pipeline. The key difference is Codex hooks fire differently — Codex uses `AGENTS.md` for configuration rather than `.claude/settings.json`, and its hook system is separate.

## Scope

- [ ] Understand Codex hook system: what events fire, what payload shape, and how to install hooks into a Codex project
- [ ] Port `status-bridge.js` for Codex: write per-session `~/.agentboard/sessions/<id>.json` with the same schema as the Claude Code bridge so the dashboard backend reads it without changes
- [ ] Port `event-logger.sh` (or write a JS equivalent) for Codex PostToolUse: same `events.jsonl` format — Edit, Write, Bash, AgentStart, WorkflowStart, WorkflowEnd events
- [ ] Port `workflow-parser.js` if Codex has a Workflow-equivalent tool; if not, map the closest analogue
- [ ] Validate that the dashboard `dashboardPanel.ts` sessions loop picks up Codex sessions correctly (provider field may differ — check `provider` in session JSON)
- [ ] Add Codex hook install instructions to `templates/codex/` and `CHEATSHEET.md`
- [ ] Test with a live Codex session: session column appears, activity feeds update, cost/context/branch show correctly
- [ ] Update `AGENTS.md.template` with the hook wiring

## Out of scope

- Any UI changes to the dashboard itself — the frontend is provider-agnostic already
- Gemini support (separate future stream)
- Changing the session JSON schema (must stay compatible with Claude Code)

## Done criteria

- [ ] Research complete: Codex hook API documented with payload shapes
- [ ] `status-bridge` Codex variant written and tested against a real session
- [ ] `event-logger` Codex variant produces valid `events.jsonl` entries
- [ ] Dashboard shows Codex sessions alongside Claude Code sessions in the Live tab
- [ ] ACTIVITY feed shows real file edits from Codex
- [ ] Git diff stats (+N/-N) appear on Codex-edited files
- [ ] Staleness detection works (session idle → sub-agents clear within 10 min)
- [ ] Hook install documented in `templates/codex/` and CHEATSHEET
- [ ] Manual QA: open dashboard with both a Claude Code and Codex session running simultaneously — both appear, both update
- [ ] `.platform/memory/log.md` appended

## Key decisions

_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-20 — Deferred until after Claude Code dashboard is stable — focus on one provider at a time, validate the schema before locking it for cross-provider use.

## Reference

- Claude Code bridge: `templates/platform/scripts/hooks/status-bridge.js`
- Claude Code event logger: `templates/platform/scripts/hooks/event-logger.sh`
- Claude Code workflow parser: `templates/platform/scripts/hooks/workflow-parser.js`
- Dashboard backend: `extensions/vscode/src/dashboardPanel.ts` — sessions loop at line ~566
- Codex config template: `templates/codex/`
- `AGENTS.md.template` — Codex agent configuration entry point
