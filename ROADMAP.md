# Agentboard Roadmap

Execution plan for closing the gap between the current Agentboard kit and a
credible multi-provider AI-workflow layer. Each phase is self-contained: it has
a goal, a scope, a concrete task list, success criteria, and an effort
estimate. Ship phases in order — each later phase assumes the earlier ones are
in place.

**Hard constraints inherited from `CLAUDE.md` (do not violate):**

- No runtime dependencies (pure bash, git, sed, grep, awk only)
- No stack pre-picking in `init`
- Templates that ship verbatim must stay stack-agnostic
- Max ~300 lines per file
- Placeholders use `{{UPPERCASE_SNAKE}}`

Any phase that would break one of these needs an explicit decision log entry
first (see "Decisions that must precede work" at the bottom).

---

## Phase 0 — Reframe the pitch (1–2 days)

**Goal:** stop overselling "manages context across providers." Agentboard does
not move conversation state between providers; it ships a shared project-truth
format plus a read-order convention that all three CLIs respect. Own that
honestly.

**Scope:** docs and CLI copy only. No code changes.

**Tasks:**

- Rewrite the README lead: "Shared work-state and project-truth for
  multi-provider AI workflows."
- Update `bin/agentboard` help banner and `--help` text to match.
- Add a "How it actually works" section to README explaining the file-first
  model: each provider's CLI auto-loads its entry file, all three entry files
  point at the same `.platform/` pack.
- Audit `CHEATSHEET.md` for the same framing.

**Success criteria:** a first-time reader of README can explain, in one
sentence, what Agentboard does and does not do.

**Effort:** ~1 engineer-day.

---

## Phase 1 — Credibility pass (1 week)

**Goal:** make the existing surface trustworthy. Catch malformed state early,
stop silent corruption on re-activation, replace hand-typed progress logs with
real git-derived evidence.

**Scope:** `bin/agentboard`, `lib/agentboard`, `templates/platform/ACTIVATE.md`,
`templates/platform/work/`, `templates/platform/domains/`.

**Tasks:**

- **Frontmatter schema check (pure bash, zero deps):**
  - Add `lib/agentboard/schema.sh` with a tiny validator that reads required
    keys + allowed enums per file type (stream, domain, repo) using awk/grep.
  - Wire into `doctor`, `new-stream`, `new-domain`.
  - Schemas live as plain text tables in `lib/agentboard/schemas/` — no YAML
    parser dependency.
- **Activation idempotency:**
  - Tag every section Agentboard generates with an HTML comment marker:
    `<!-- agentboard:section=decisions v=1 -->` and closing marker.
  - Re-running activation replaces tagged sections in place instead of
    appending. User-authored content between markers is preserved.
  - Add a `--dry-run` flag that prints the diff without writing.
- **Git-derived progress log:**
  - New subcommand `agentboard log <stream-slug>` that runs
    `git diff --stat <base>..HEAD` scoped to stream files plus code touched
    on the stream branch, and appends a timestamped block to the stream's
    progress log section.
  - Retain the manual note field, but stop relying on the LLM to self-report
    edits.
- **Post-activation doctor gate:**
  - ACTIVATE.md's final step runs `agentboard doctor` automatically. Bad
    frontmatter fails activation loudly instead of surviving silently.

**Success criteria:**

- `doctor` rejects a stream file missing required frontmatter keys.
- Running activation twice on the same project produces a clean diff with no
  duplicated sections.
- `agentboard log <slug>` output ends up in the stream file verbatim.

**Effort:** ~5 engineer-days.

---

## Phase 2 — Visibility (3 days)

**Goal:** give the human operator a live view of `ACTIVE.md` without opening
the file. Highest user-visible credibility gain per hour spent in the whole
roadmap.

**Scope:** one new subcommand, zero changes to the data model.

**Tasks:**

- `agentboard tui` — read-only terminal dashboard that renders `ACTIVE.md` as
  a sortable table (stream | type | status | owner | updated | branch).
- Filter flags: `--status in-progress`, `--owner <name>`, `--repo <slug>`.
- Color coding from ANSI escapes only (no `gum`, no external deps).
- Auto-refresh every N seconds via plain `while` loop + `clear`.

**Success criteria:**

- On a project with 10+ streams, `agentboard tui --status in-progress` shows
  only live work in under 200ms.
- Works on stock macOS bash 3.2.

**Effort:** ~3 engineer-days.

---

## Phase 3 — Multi-provider enforcement parity (1 week)

**Goal:** close the honesty gap where Claude Code has the closure-gate hook
and Codex/Gemini do not. Either reach parity or state plainly in the README
that enforcement is Claude-only. Do not leave the current ambiguous state.

**Scope:** hooks or equivalent pre-tool interception in each CLI.

**Tasks:**

- **Research phase (1 day):** map Codex CLI and Gemini CLI extension/hook
  surfaces. Document in a decision log entry what each CLI supports.
- **Codex parity:** if Codex CLI exposes an MCP or pre-tool hook, port the
  closure-gate logic from `platform-closure-gate.js` to the Codex surface.
- **Gemini parity:** same for Gemini CLI's extension mechanism.
- **Fallback path:** if a CLI has no hook surface, ship a pre-commit git hook
  that enforces the same invariant at commit time. Less tight than runtime
  enforcement but better than nothing.
- Update README to state current enforcement coverage per provider honestly.

**Success criteria:**

- Attempting to set `closure_approved: true` on a stream that still has open
  done-criteria items is blocked in all three CLIs — or the README states
  which providers lack the gate and why.

**Effort:** ~5 engineer-days, mostly research and surface discovery.

---

## Phase 4 — Budget-aware handoff (1 week)

**Goal:** today's `handoff` prints a fixed load order. It does not know that
Codex's context is smaller than Claude's. Give `handoff` a token budget so it
can tailor the pack per provider.

**Scope:** `bin/agentboard handoff`, stream/domain templates, new optional
summary files.

**Tasks:**

- **Tier 1 — budget flag:** `agentboard handoff <slug> --budget 8k` includes
  only the brief + stream file + primary domain, skipping secondary domains
  and repo refs when the estimated token count exceeds the budget.
- Token estimation: bytes-to-tokens heuristic (1 token ≈ 4 bytes of English
  markdown) — good enough, zero deps.
- **Tier 2 — per-stream summary file:** `agentboard summarize <slug>` writes
  `<slug>.summary.md` next to the stream file. Deterministic prompt shipped
  in `templates/platform/agents/summarize.md`, executed by the active LLM in
  the session. Committed to git so summaries are auditable.
- When `--budget` pressure is high, `handoff` prefers the summary over the
  full stream file.
- Tier 3 (adaptive, per-provider tokenizer) is explicitly deferred — see
  Phase 6.

**Success criteria:**

- `agentboard handoff <slug> --budget 4k` produces a load order whose total
  byte size stays under the byte-equivalent of the budget.
- A summary file, once committed, is preferred over the raw stream file
  when the budget is tight.

**Effort:** ~5 engineer-days.

---

## Phase 5 — Concurrency model (1–2 weeks)

**Goal:** today two agents editing the same stream file produce a silent
merge conflict. Ship a concurrency primitive that Agentboard enforces, not
just advises.

**Scope:** `claim`, `release`, `doctor`, stream file frontmatter.

**Tasks:**

- **Decision first:** choose between `flock(1)` advisory-locks and the
  git-branch-per-stream model. Recommendation: git-branch-per-stream,
  because it matches the file-first philosophy and survives Dropbox/NFS
  vaults.
- Enforce: editing `work/<slug>.md` requires being on branch
  `stream/<slug>` (or a designated override branch). `doctor` fails the
  check if violated.
- `agentboard claim <slug>` creates/switches to the stream branch.
- `agentboard release <slug>` returns to the main/default branch and marks
  the stream as unclaimed in `ACTIVE.md`.
- Cross-agent signaling: `ACTIVE.md` owner column becomes the authoritative
  claim record. Multiple concurrent claims are caught by `doctor` and by
  the Phase 3 pre-tool hook.

**Success criteria:**

- Two agents cannot both have `claim` open on the same stream without
  `doctor` flagging it.
- A stream edit on the wrong branch is blocked before write.

**Effort:** ~10 engineer-days including tests.

---

## Phase 6 — Adaptive context (2–4 weeks, optional)

**Goal:** Tier 3 from Phase 4 — per-provider tailored handoff packs using
real tokenizer math instead of a byte heuristic. This is the one genuinely
hard problem on the roadmap. Do not start until Phases 0–5 are shipped and
users are asking for it.

**Scope:** new per-provider token counters, cached token measurements per
file, `handoff --provider claude|codex|gemini`.

**Open questions (resolve before starting):**

- Where do tokenizer implementations live without violating the
  no-runtime-deps rule? Candidates: ship as optional binaries users install
  themselves; emit rough counts via a single shelled-out `python -c` only
  when the user opts in.
- How is the cache invalidated? Per-file mtime vs. content hash.

**Effort:** ~20+ engineer-days. Treat as a funded sprint, not an evening.

---

## Cross-cutting concerns

**Tests:** every phase ships with unit tests under `tests/unit/` and extends
`tests/integration.sh` where the new surface is user-visible. No phase
merges without green tests.

**Docs:** README lead, CHEATSHEET, and the template that `init` drops at the
project root all stay in sync. A phase that changes user-visible behavior
must ship its own docs patch in the same change.

**Backward compatibility:** existing `.platform/` folders from prior
Agentboard versions must keep working. Phase 1's schema check should warn
on legacy files, not fail. A `migrate` command already exists — extend it,
don't replace it.

**Explicitly out of scope:**

- A web UI. The "Phase 3 UI" mentioned in older design notes is not on this
  roadmap. A TUI (Phase 2) covers the operator case; a web UI is a separate
  product decision.
- Auto-ingestion from code (parsing AST, inferring domains from imports).
  Activation is LLM-driven on purpose — auto-ingestion fights that design.
- Cloud sync / hosted state. Agentboard stays local-first and
  git-as-transport.

---

## Decisions that must precede work

These are prerequisites, not tasks. Each one needs a short decision-log
entry (in whatever decision log the repo adopts — `decisions.md` at the
root is fine) before the corresponding phase starts:

1. **Phase 1:** schema format — shipped as bash-readable tables vs. a YAML
   file parsed by awk. Recommendation: bash tables for zero-dep purity.
2. **Phase 3:** per-CLI enforcement strategy — runtime hook vs. git
   pre-commit fallback.
3. **Phase 5:** concurrency primitive — `flock(1)` vs.
   git-branch-per-stream.
4. **Phase 6:** tokenizer delivery — whether to relax the
   no-runtime-deps rule and how.

---

## Prioritization summary

If forced to ship only the next two weeks of work, ship **Phase 0 +
Phase 1 + Phase 2 + Phase 4 Tier 1**. That covers ~80% of the credibility
gap with zero genuinely hard problems. Phases 3, 5, and 6 address real
weaknesses but require research and decisions before code.
