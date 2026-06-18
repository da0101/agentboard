# Agent Rules

> **Audience:** any AI agent working on this project.
> **Authority:** these rules supplement `workflow.md`. When they conflict, the more restrictive rule wins.

---

## Must always

1. **Delegate to specialists.** Match every task to the appropriate role in `roles/INDEX.md` before starting. Cross-cutting work uses the team-lead role.
2. **Check memory and decisions before proposing.** Read `memory/decisions.md` and grep `memory/learnings.md` for the symptom before proposing a solution. Don't re-derive a known answer.
3. **Research before new streams.** Every new stream requires a research pass (local code + targeted web) before proposing. Scale depth to risk; never skip entirely.
4. **Test before claiming done.** Run the relevant test suite and read the full output — exit codes, not just last lines — before reporting success.
5. **Validate at system boundaries.** Validate all external inputs (API payloads, user input, env vars) at the boundary. Do not validate internal data that was already validated upstream.
6. **Reuse before creating.** Search the codebase for an existing component or utility that covers the need. Extend with a parameter before building a parallel implementation.
7. **Prefer immutable state.** Represent state as derived values where possible. Mutations must be explicit, localized, and justified.

---

## Must never

1. **Include secrets, tokens, or absolute local paths in any file.** Credentials, API keys, and machine-specific paths must never appear in source, templates, or docs. Use env vars or secret managers.
2. **Skip tests for new code.** Every new function, component, and provider must have unit tests. "I'll add tests later" is not an exit condition for Stage 6.
3. **Bypass security checks.** Auth, permission checks, and data-access boundaries are not optional. Never comment them out, stub them, or route around them without explicit human sign-off.
4. **Duplicate code without justification.** Copy-paste requires a written reason in the stream file. If the same pattern appears twice, extract it.
5. **Self-declare a stream complete.** Present evidence and propose closure. The human owner makes the final call. No exceptions.
6. **Commit before Stage 6 passes and the human approves.** Execute produces code. The commit happens after tests pass, security is clear, and the owner says "ship it."
7. **Write plan `.md` files.** Plans live in chat. `work/` stream files are operational state, not plan documents.

---

## Memory rules

| When | Where | What |
|---|---|---|
| Before diagnosing a bug | `memory/learnings.md` | Grep for symptom keyword — do not re-diagnose known classes |
| Before proposing anything | `memory/decisions.md` | Read locked decisions; do not re-open them without new evidence |
| After a non-obvious bug | `memory/learnings.md` | Append an L-NNN entry with symptom, root cause, fix, class |
| After any successful task | `memory/log.md` | Append one line: `YYYY-MM-DD — <task> — <outcome> — <takeaway>` |
| After a stable architectural insight | `memory/MEMORY.md` | Add a cross-session invariant that would save the next agent time |
| Backlog item found out of scope | `memory/BACKLOG.md` | Append one row; do not open a new stream |

---

## Hook behavior

Hooks in `scripts/hooks/` run automatically. Understand their contract before editing code they guard.

| Hook | Trigger | Fail behavior |
|---|---|---|
| `bash-guard.sh` | pre-commit | **Fail-closed.** Blocks commit if bash files exceed the line-count cap. Fix the file, then retry. |
| `platform-closure-gate.js` | pre-commit | **Fail-closed.** Blocks commit if a stream file has `closure_approved: false`. The human must flip it. |
| `platform-bootstrap.sh` | post-checkout | **Fail-open.** Warns if `.platform/` is missing but does not block. Run `agentboard init` to fix. |

Exit code rules: hooks exit `0` on pass, `1` on hard block, `2` on soft warn. A `2` exit does not block the commit. Never use `--no-verify` to skip hooks — surface the underlying issue instead.
