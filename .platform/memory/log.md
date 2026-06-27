# Session Log

One line per completed task. Newest at the top. Append-only.

Format: `YYYY-MM-DD — <task> — <outcome> — <takeaway>`

2026-06-20 — Released vscode extension 2.1.0 with live dashboard, workflow tracking, catalog expand, git diff stats, security fixes. 2.1.1 prep: audit + rescan pass.
2026-06-12 — graphify-integration stream — shipped ab-graphify skill + init prompt + ACTIVATE.md step across all three provider templates
2026-04-30 — closed: skills-baseline-testing — pressure-tested 5 ab-* skills, patched ab-debug/security/workflow with rationalization counters, all 3 re-passed; 2 real bugs found as side-effects (close row deletion, brief domain display)
2026-04-30 — closed: skills-improvement — overhauled all 10 ab-* skills: trigger descriptions, ab-qa browser auth, targeted fixes per skill, synced .claude/.agents; shipped in v1.9.0
2026-04-30 — closed: research-first-stream-workflow — research-first intake rule landed in ab-triage/workflow/research; mandatory for all new streams regardless of size
2026-04-30 — closed: search-command — agentboard search shipped and verified working against .platform/ files
2026-04-30 — closed: event-log-dedup — dedup fix shipped, no duplicate FileChange events reported since 2026-04-18; user confirmed done
2026-04-30 — fix: ab close ACTIVE.md bug — _close_remove_from_active_registry was deleting the row instead of marking it closed; fixed to update status column to "closed" and added stream_rows_from_active filter to exclude closed rows from handoff/count; regression test written first, existing test updated; ACTIVE.md template lifecycle table updated with closed status
2026-04-28 — tool-quality-uplift — shipped: watch_install_test fully fixed (stub rename + systemd unit name), _ab_check_unreasoned_changes added to session-track.sh + wired into codex-ab/gemini-ab exit, _close_print_domain_gap added to close harvest checklist, lock release fixed with ${provider}-anonymous fallback; tool moved from ~6.5 to ~9.0 quality
2026-04-19 — handoff-snippets — shipped: agentboard handoff now auto-searches domain files and shows targeted excerpts inline; --no-snippets to skip; grep context separators (--) must be filtered with awk since GNU/BSD grep have no portable --no-group-separator; head() shell function in core/base.sh shadows system head — always use awk NR<=N instead
2026-04-19 — search-command — shipped: agentboard search with ripgrep/grep fallback, OR-join, scope flags, token estimates — instruction-driven approach works for Claude + Codex + Gemini without needing MCP; BM25-style OR search on well-structured .platform/ files is ~85% as good as semantic search at zero infrastructure cost

---
- 2026-06-23 — commit `02028cd`: wip: add index and distill commands; auto-distill on stream close — auto-logged
- 2026-06-22 — commit `c66a1a3`: fix: context menu for large files, foldable KPI/session sections, remove redundant SESSION block in tab view — auto-logged
- 2026-06-20 — commit `6088dbc`: chore: add codex dashboard support stream + 2.1.0 staleness + workflow scroll fixes — auto-logged
- 2026-06-20 — commit `652abca`: feat: vscode extension 2.1.0 — real-time dashboard with workflow + catalog — auto-logged
- 2026-06-18 — commit `be76239`: fix: global ~/.agentboard/live.json bridges across VS Code windows — no more blank dashboard — auto-logged
- 2026-06-18 — commit `6311e8a`: fix: smart workspace root detection — prefer folder with .platform/ or active HUD file — auto-logged
- 2026-06-18 — commit `1dc1b07`: feat: stream accordion with objective, done criteria, next action, open-in-editor — auto-logged
- 2026-06-18 — commit `56f2749`: feat: robust workflow agent parser, show roster with role/skill/model even when 0 parsed — auto-logged
- 2026-06-18 — commit `5a23cd6`: feat: parse workflow script to show all agents with role/skill/model in dashboard — auto-logged
- 2026-06-18 — commit `79db718`: feat: role+skill per agent — PreToolUse hook, label format, dashboard rendering — auto-logged
- 2026-06-18 — commit `520005d`: feat: capture Agent tool dispatches, show agents panel in Live tab — auto-logged
- 2026-06-17 — commit `9dedcea`: fix: capture skill reads + all Bash commands in event-logger — auto-logged
- 2026-06-17 — commit `2326c35`: feat: detect compaction state (context >75% + long op) in NOW block — auto-logged
- 2026-06-17 — commit `62e45d8`: redesign: NOW block shows last action + deduplicated file activity — auto-logged
- 2026-06-17 — commit `ef35d12`: fix: show role mission as description in Catalog roles column — auto-logged
- 2026-06-17 — commit `2808db9`: fix: Commands column shows 14 ab CLI commands, not skills — auto-logged
- 2026-06-17 — commit `60ccca3`: feat: capture /skill invocations in event-logger, show agent count, skill in activity — auto-logged
- 2026-06-17 — commit `246378f`: fix: postMessage architecture prevents tab reset on data updates — auto-logged
- 2026-06-17 — commit `b988380`: feat: two-tab dashboard (Live + Catalog), agent info panel, ECC-style catalog view — auto-logged
- 2026-06-17 — commit `677f763`: fix: worktree object rendering, strip model name from role display — auto-logged
- 2026-06-17 — commit `2148534`: feat: add active stream, role, activity feed to dashboard; fix HudAgent types — auto-logged
- 2026-06-17 — commit `b73ade2`: feat: add statusLine hook (status-bridge.js) for live model/cost/context data — auto-logged
- 2026-06-17 — commit `2fa9bd1`: fix: parse sessions/worktrees from CP response object, show CP status correctly — auto-logged
- 2026-06-17 — commit `a74e5a2`: fix: pipe SQL via stdin to fix sqlite3 quoting, add WebviewPanel dashboard — auto-logged
- 2026-06-17 — commit `26b790e`: fix: add @types/node and repository field to VS Code extension package.json — auto-logged
- 2026-06-17 — commit `50ece85`: chore: release 2.0.0 — agentboard OS — auto-logged

2026-06-15 — closed stream qa-execution-journal → ./.platform/work/archive/qa-execution-journal.md (by danilulmashev)

2026-06-14 — closed stream manual-qa-artifact-gate → ./.platform/work/archive/manual-qa-artifact-gate.md (by danilulmashev)

2026-06-14 — closed stream silicon-valley-mindset → ./.platform/work/archive/silicon-valley-mindset.md (by danilulmashev)

2026-05-13 — closed stream sync-command-fallback → ./.platform/work/archive/sync-command-fallback.md (by danilulmashev)

2026-05-13 — closed stream manual-qa-plan-workflow → ./.platform/work/archive/manual-qa-plan-workflow.md (by danilulmashev)

2026-04-28 — closed stream tool-quality-uplift → ./.platform/work/archive/tool-quality-uplift.md (by danilulmashev)
- 2026-04-28 — commit `87e59d2`: feat: log-reason exit reminder, domain gap check, watch test fixes — auto-logged
- 2026-04-28 — commit `bb1e712`: fix: lock release fails when AGENTBOARD_SESSION_ID is not set — auto-logged
- 2026-04-28 — commit `9fbd0ac`: feat: surface Reason events + stale domain warnings in handoff and brief — auto-logged
- 2026-04-28 — commit `baed1ec`: Merge branch 'main' of github.com:da0101/agentboard — auto-logged

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
2026-04-27 — Add research-first new-stream workflow — all providers now require scaled research, targeted external research, phased planning, and human approval before implementing a new stream
2026-05-13 — brief startup icons — neutralized brief section headers and zero-stream copy while preserving gotcha severity — normal startup no longer looks like an error state
2026-05-13 — brief gotcha icons — rendered stored gotcha severity as 📌/💡/📝 in startup output — memory priority remains sortable without red/yellow error-looking markers
2026-05-13 — manual QA plan workflow — Stage 6 now requires guided manual QA steps when human verification matters — future handoffs should tell developers and QA exactly how to test
2026-05-13 — sync command fallback — `ab sync` now gives public-command recovery guidance, `ab update` restores missing `sync-context.sh`, and templates now say `ab sync --apply` instead of direct script invocation
2026-05-13 — sync-context executable mode — multi-repo update rewrites `sync-context.sh` after injecting repo paths, so chmod must run after that rewrite and the shared writer preserves executable mode
2026-05-13 — worktree branch workflow — new feature/bugfix/hotfix streams now require isolated worktrees, dependency installation, and localhost port discovery before coding — concurrent multi-repo work starts from clean filesystem boundaries
2026-06-11 — role profiles pack — shipped 16 role files + INDEX.md routing table; roles activate by intent-matching not keywords; pair-programmer is the silent fallback (v1.13.0)
2026-06-11 — ab rescan command — new CLI command + RESCAN.md protocol; agent re-reads codebase and updates domains/architecture/conventions/STATUS without touching decisions/ACTIVE/BRIEF (v1.14.0)
2026-06-12 — model-tier system — every role and skill file now carries explicit model guidance; ab-workflow hard rule #10 requires self-audit of all agent() calls for missing model: param before Workflow() submission; workflow.md + CLAUDE.md templates add Fable tier and workflow-agent warning (v1.15.0)
2026-06-13 — code cleanup skill/role — added `ab-cleanup` and `code-cleanup-engineer`, wired role routing/provider skill lists, carried main-side Graphify source/runtime files forward, and ignored `.platform/graphify/cache/`
2026-06-14 — QA self-heal skill/role — added `ab-qa-self-heal` and `qa-automation-engineer`, wired provider skill lists and role routing, and locked safety/report/install contracts for Maestro/browser/app-driving loops
2026-06-14 — Silicon Valley product mindset — added provider-neutral workflow, role, root-entry, and contract-test coverage so PM/engineering agents pursue best-in-class product ambition with explicit scope and approval guardrails
2026-06-15 — manual QA artifact gate — upgraded manual QA from chat-only final plan to stream-scoped markdown artifact gate with archived QA history — future agents must ship with executable QA evidence or a documented not-required reason
2026-06-15 — QA execution journal — added a chronological journal requirement for LLM-driven interactive QA so Maestro/browser agents document what they did, saw, fixed, retested, passed, skipped, and escalated
2026-06-26 — Codex dashboard telemetry — Codex now emits Claude-compatible session snapshots and dashboard-readable file activity through native hooks plus wrapper fallback
2026-06-27 — debug: VS Code dashboard cross-project session leak — fixed root cause: dashboard session ingestion now filters ~/.agentboard live session files by canonical workspace root before rendering active sessions
2026-06-27 — debug: VS Code dashboard stale HUD ghost status — fixed root cause: dashboard trusted old agentboard.hud-status.json snapshots forever; HUD data is now ignored after the freshness window
2026-06-27 — debug: VS Code dashboard raw Codex invisibility — fixed root cause: raw Codex CLI processes do not write Agentboard session snapshots; dashboard now detects matching local Codex processes by workspace cwd as unbridged sessions
2026-06-27 — debug: VS Code dashboard raw Codex empty activity — fixed root cause: raw Codex fallback sessions were created with empty activity while the UI preferred the single session's activity over workspace KPI activity; raw sessions now carry best-effort workspace activity
2026-06-27 — debug: VS Code refactor menu forced Claude — fixed root cause: the dashboard message router hard-coded `claude` for new refactor sessions; provider launch is now selected explicitly and uses Agentboard wrappers for Codex/Gemini when present
