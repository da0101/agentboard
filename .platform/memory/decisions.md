# Agentboard — Decision Log

Last updated: 2026-04-17

> **Purpose:** capture the _why_ behind architectural, product, and tooling decisions so future AI sessions and developers don't have to re-derive them (or undo them).

---

## Format

Each decision is one row. **Locked** decisions are final until a new decision supersedes them. **Deferred** decisions are explicit non-decisions with a trigger for when to revisit.

| # | Date | Status | Topic | Decision | Why | Rejected alternatives |
|---|---|---|---|---|---|---|

---

## Locked decisions

_Decisions that are final. If you want to change one of these, write a new decision row that supersedes it — don't silently overwrite._

| # | Date | Topic | Decision | Why | Rejected alternatives |
|---|---|---|---|---|---|
| 1 | 2026-04-17 | Language | Pure bash only | Zero install friction across macOS/Linux; no npm/venv/runtime; agents can modify the tool with just a text editor | Node.js (install burden + adds drift), Python (venv pain), Go (compile step kills rapid iteration) |
| 2 | 2026-04-17 | Bash version | Target bash 3.2 (macOS default) | macOS ships 3.2 and Apple will never upgrade it; requiring bash 5 would break install on every Mac | bash 4+ features (associative arrays, `${var^^}`, `mapfile`) |
| 3 | 2026-04-17 | State format | Markdown + YAML frontmatter | Human-readable, diff-friendly, loadable by any LLM, queryable by frontmatter_value(); JSON would require jq dep | JSON (needs jq), SQLite-only (opaque to LLMs), custom binary (hostile to everything) |
| 4 | 2026-04-17 | Activation model | LLM fills .platform/ at activation, tool never pre-picks stack | Static stack templates rot; the LLM reading actual code produces correct output the first time | Shipping React/Django/etc. templates (would need per-stack maintenance + always wrong) |
| 5 | 2026-04-17 | File size | ~300 lines per bash file as soft cap | Keeps files single-purpose; forces splits when commands accrete logic | Hard linter enforcement (too rigid, we already violate on usage.sh/streams.sh where coupling justifies it) |
| 6 | 2026-04-17 | Enforcement | Claude Code PreToolUse hooks for commits + destructive ops; honor system for Codex/Gemini | Hard enforcement only where CLI exposes hook API; cross-CLI commit guarding would require shell shims (invasive) | Git pre-commit hooks (fire on commits not on agent actions), PATH shims (invasive, fragile across shells) |
| 7 | 2026-04-17 | Memory format | `.platform/memory/` folder with 7 append-only files + marker-bounded sections | Single location for durable knowledge; markers let `brief`/`close` parse reliably; bounded growth via log trim-to-10 | Database (opaque), per-stream memory (doesn't compound), unstructured files (can't be parsed for `brief`) |
| 8 | 2026-04-17 | Usage tracking | SQLite at ~/.agentboard/usage.db, cumulative-delta mode on log | SQLite is on every modern OS by default; cumulative mode prevents double-counting when LLMs report running totals | Flat JSON file (slow at scale), OpenTelemetry (overkill), delta-only mode (forces agents to track deltas manually) |
| 9 | 2026-04-17 | Dogfooding | Agentboard runs on its own repo with `.platform/` gitignored | Real usage data > theoretical design; bugs surface via our own workflow; streams track our own features | Not dogfooding (we'd keep shipping theater), committing .platform (pollutes the kit repo with instance state) |
| 10 | 2026-04-17 | Watch scheduler | Use launchd (macOS) + systemd user timer (Linux), not cron | Cron requires crontab-merge (clobber risk); launchd/systemd coalesce missed runs natively; user-level avoids sudo | Cron (merge risk), nohup (no reboot survival), system-wide units (requires sudo) |
| 11 | 2026-04-17 | Watch signal quality | Rank changed files before auto-checkpointing; prefer stream-relevant files over lexically early scaffolding noise | Raw `git status` order surfaces `.claude/skills/*` before actual work files; ranking makes auto-checkpoints meaningful | No ranking (produces misleading summaries), semantic diff analysis (out of scope) |
| 12 | 2026-04-17 | Usage attribution | Semantic task types (`design`, `implementation`, `debug`, `audit`, `handoff`) logged separately from complexity labels | Generic labels (normal/heavy/trivial) hide spend root causes; task types reveal where tokens actually went | Complexity only (masks the why), per-message telemetry (out of scope) |
| 13 | 2026-04-18 | Session→stream binding | Persist session-id → stream-slug mapping in `.platform/.session-streams.tsv` (tab-delimited, one row per session) | Lets event-logger and wrappers attribute events to the right stream across tool calls without passing context explicitly; TSV is shell-parseable with no deps | In-memory only (lost on restart), SQLite (adds dep), env var only (breaks when multiple streams are open) |
| 14 | 2026-04-18 | Event log content policy | `events.jsonl` captures only code-file edits (Edit/Write/MultiEdit to non-.platform/ files), git commits/pushes, and Reason annotations — all other tool events dropped | The log's job is provider handoff ("here's what I changed and why"), not a full audit trail; noise (Read, Bash, .platform/ meta-writes) obscures signal and bloats the handoff view | Full PostToolUse capture (too noisy), manual-only logging (agents forget), separate noise/signal logs (doubles the surface) |
| 15 | 2026-04-18 | Stream resolution hardening | Canonical stream resolution must ignore stale env/brief state unless it still resolves to a real stream file, and callers should fall through to active context instead of failing hard on dead references | Closed streams routinely linger in `AGENTBOARD_STREAM`, session maps, and `BRIEF.md`; treating stale state as fatal poisons handoff, logging, and startup attribution | Trusting env/brief blindly (misattributes work), failing resolution on dead state (breaks active inference), duplicating ad hoc fallback logic in each caller |
| 16 | 2026-04-18 | Lock ownership | File locks are owned by session identity, not provider identity; provider remains descriptive metadata only | Same-provider concurrency is normal in multi-agent work. Provider-scoped locks let a second Codex or Claude session bypass the queue and falsely appear idempotent | Provider-only ownership (collides across sessions), per-provider shared locks (can’t model queueing correctly), no session IDs in hooks/CLI (breaks release correctness) |
| 17 | 2026-04-18 | FileChange dedup | Non-Claude file-change pollers share persisted per-file diff fingerprints in `.platform/.file-change-state.tsv`, and emit a new row only when that fingerprint changes | In-memory filename sets only dedupe inside one poller process; concurrent wrappers and restarted pollers replay the same dirty snapshot and pollute the event log | Per-process memory only (replays across wrappers), event-log post-processing (loses real-time signal), daemon-only dedup (breaks fallback path) |
| 18 | 2026-04-27 | New stream intake | Every new stream requires scaled research, targeted external research, a research-backed phased plan, and explicit human approval before implementation | New streams are where vague requirements and premature code create the most downstream churn; research + approval keeps Codex, Claude, and Gemini aligned before side effects | Research only for medium+ streams (misses small-but-ambiguous work), provider-specific rules (drift), implementation before approval (weak human-in-loop) |

---

## Deferred decisions

_Explicit non-decisions. Each has a trigger for when to revisit._

| # | Date | Topic | Current non-decision | Trigger to revisit |
|---|---|---|---|---|
| 1 | 2026-04-17 | _Example_ | _We're not deciding this yet_ | _When X happens_ |

---

## How to add a decision

1. Use the highest unused `#`.
2. Fill date, status, topic, decision, why, rejected alternatives.
3. If this supersedes a prior decision, reference it: "Supersedes #N".
4. If it's deferred, include a trigger condition.
5. Commit with message: `Record decision #N: <topic>`.
