# Session Log

One line per completed task. Newest at the top. Append-only.

Format: `YYYY-MM-DD — <task> — <outcome> — <takeaway>`

2026-04-19 — handoff-snippets — shipped: agentboard handoff now auto-searches domain files and shows targeted excerpts inline; --no-snippets to skip; grep context separators (--) must be filtered with awk since GNU/BSD grep have no portable --no-group-separator; head() shell function in core/base.sh shadows system head — always use awk NR<=N instead
2026-04-19 — search-command — shipped: agentboard search with ripgrep/grep fallback, OR-join, scope flags, token estimates — instruction-driven approach works for Claude + Codex + Gemini without needing MCP; BM25-style OR search on well-structured .platform/ files is ~85% as good as semantic search at zero infrastructure cost

---

2026-04-18 — closed stream daemon-orchestration → ./.platform/work/archive/daemon-orchestration.md (by danilulmashev)

2026-04-18 — completed daemon-orchestration hardening — lock ownership is now session-scoped, non-Claude wrappers announce lock discipline, and lock TTL plus same-provider queueing are covered by focused tests — the stream state now matches the implementation

2026-04-18 — closed stream stream-resolution-hardening → ./.platform/work/archive/stream-resolution-hardening.md (by danilulmashev)

2026-04-18 — completed stream-resolution-hardening — stale stream resolution now falls through to active state, `new-stream` repairs invalid BRIEF/ACTIVE bookkeeping, and focused regressions cover both paths — stream attribution no longer trusts dead env or brief references

2026-04-18 — closed stream framework-audit → ./.platform/work/archive/framework-audit.md (by danilulmashev)

2026-04-18 — closed stream platform-hardening → ./.platform/work/archive/platform-hardening.md (by danilulmashev)

2026-04-18 — completed framework-audit — Agentboard is useful and materially solves resumable work-state, but multi-stream event attribution, transient-state hygiene, and full automation parity still need work
2026-04-18 — handoff-focused event filtering — Read/meta-edits/plain Bash all dropped; only code writes + git commits + Reasons remain — events.jsonl now tells exactly the developer-handoff story
2026-04-18 — lean events + aliases.sh + current-stream/next-action commands — committed; all tests pass — duplicate event sources (file poller + meta-call Bash) both fixed; events.jsonl now carries only signal fields
2026-04-18 — released v1.6.0 — install-hooks --aliases, wrapper loop fix, README completeness, CLI phrase shortcuts in commands.md — phrase→command table ships on agentboard update to all projects
2026-04-18 — closed stream watch-install → ./.platform/work/archive/watch-install.md (by danilulmashev)

2026-04-18 — closed stream usage-intelligence-upgrade → ./.platform/work/archive/usage-intelligence-upgrade.md (by danilulmashev)

2026-04-18 — closed stream watch-signal-quality → ./.platform/work/archive/watch-signal-quality.md (by danilulmashev)

2026-04-18 — closed stream platform-quality-fixes → ./.platform/work/archive/platform-quality-fixes.md (by danilulmashev)

2026-04-17 — Initialized project with agentboard — created .platform/ context pack — workflow, conventions, and templates are in place; next task is to fill STATUS.md and architecture.md
2026-04-18 — Add Node daemon for parallel cross-provider orchestration — appendFileSync in daemon serializes concurrent writes; daemon-first + JSONL fallback keeps all paths working
2026-04-18 — Add file-lock queue (Phase 2 daemon-orchestration) — daemon holds lock state; Claude enforced via PreToolUse hook; Codex via honor-system CLI; auto-expire at 5min prevents deadlock
2026-04-18 — Add log-reason command — LLMs annotate WHY after writes; stored as Reason events in events.jsonl; mandatory in all three provider templates
2026-04-18 — Add events rotation + codex/gemini model selection — rotation prevents unbounded growth; effort/model prompt logs tier in SessionStart so usage reports can break down cost by complexity
2026-04-18 — debug: duplicate FileChange events — fixed root cause: non-Claude pollers now share persisted per-file diff fingerprints instead of per-process filename memory — concurrent wrappers stop replaying the same dirty snapshot, while real later edits still emit
