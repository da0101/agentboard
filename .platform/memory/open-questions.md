# Open questions

_Live hypotheses and unresolved questions. Appended during `agentboard close <slug>` when a stream surfaced something that couldn't be answered. Moved to Resolved when a later stream answers them._

---

## Active

<!-- agentboard:open-questions:active:begin -->
<!-- Format: `- YYYY-MM-DD — [domain] question (context)` -->
- 2026-04-18 — [event-logger] Should stream-resolution helpers be extracted from `event-logger.sh` inline into a shared sourced library, eliminating the duplication with `project_state.sh`? (Blocked on bash sourcing from hook context — hooks run in arbitrary cwd)
- 2026-04-18 — [runtime artifacts] Should transient files (events.jsonl, .daemon-port, .session-streams.tsv) move under `.platform/runtime/` to make the boundary explicit, or stay under `.platform/` with .gitignore coverage?
- 2026-04-18 — [automation parity] Does the current automation meaningfully protect against human process drift outside Claude Code hooks? (Framework audit found Codex/Gemini still rely more on process discipline and setup hygiene)
<!-- agentboard:open-questions:active:end -->

## Resolved

<!-- agentboard:open-questions:resolved:begin -->
<!-- Format: `- YYYY-MM-DD — [domain] question → answer (stream: <slug>)` -->
<!-- agentboard:open-questions:resolved:end -->
