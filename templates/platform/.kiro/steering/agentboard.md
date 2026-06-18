# Agentboard Steering — Session Protocol

## Read at session start

Before doing any work, read these files in order:

1. `.platform/work/BRIEF.md` — current sprint brief, priorities, and in-scope context.
2. `.platform/work/ACTIVE.md` — active stream name, current stage, and next action.
3. `.platform/STATUS.md` — overall feature status and immediate priorities.

If `.platform/` does not exist, the project has not been activated. Suggest: `agentboard init` followed by the activation prompt.

## Workflow stages

Follow the 6-stage protocol from `.platform/workflow.md`:

1. **Triage** — classify type, scope, and risk.
2. **Research** — mandatory for new streams; bounded (1 search + 3 reads max).
3. **Propose** — present plan in chat with phases, risks, mitigations, alternatives, tests, and rollback path. Wait for human approval.
4. **Execute** — implement in an isolated Git worktree (`feature/<slug>` from `develop`).
5. **Verify** — run tests, lint, manual QA if applicable.
6. **Log** — append one line to `.platform/memory/log.md`.

## Hard rules

- Never self-declare a stream complete. Present evidence; let the developer close it.
- Read `.platform/memory/decisions.md` before proposing any architectural change.
- Plans live in chat, not in extra `.md` files.
- Do not delete or overwrite `.platform/memory/` files; only append.

## Reference

| File | Purpose |
|---|---|
| `.platform/workflow.md` | Full 6-stage protocol |
| `.platform/architecture.md` | System design and invariants |
| `.platform/memory/decisions.md` | Locked decisions |
| `.platform/memory/log.md` | Session history |
| `.platform/conventions/` | Per-stack coding conventions |
