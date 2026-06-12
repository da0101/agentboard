# Graphify Integration Design

**Date:** 2026-06-12
**Status:** Approved
**Scope:** agentboard CLI + skill pack

---

## Problem

Agentboard scaffolds a `.platform/` context pack but gives the LLM no structured map of the codebase itself. On large projects, agents grep through files linearly instead of querying relationships. Graphify solves this by turning any codebase into a queryable knowledge graph (`graph.html`, `GRAPH_REPORT.md`, `graph.json`).

---

## Goals

1. Surface graphify at `ab init` time with zero friction — detect it, prompt if present, tip if absent.
2. Make all three providers (Claude Code, Codex, Gemini CLI) aware of graphify and how to use it via identical skill content.
3. No required dependency — graphify is always optional; agentboard never fails when it is absent.

---

## Architecture

Four changes, one new file:

| Change | File | Type |
|---|---|---|
| New | `lib/agentboard/commands/graphify_prompt.sh` | New bash source file (<300 lines) |
| Edit | `bin/agentboard` | Source new file |
| Edit | `lib/agentboard/commands/init.sh` | Call `_graphify_maybe_prompt` (replaces one blank line, net 0 growth — file frozen at 348) |
| New | `templates/skills/ab-graphify/SKILL.md` | New skill, deploys via `ab update` |
| Edit | `templates/root/CLAUDE.md.template` | Add graphify step + skill to list |
| Edit | `templates/root/AGENTS.md.template` | Same |
| Edit | `templates/root/GEMINI.md.template` | Same |

---

## Component 1: `lib/agentboard/commands/graphify_prompt.sh`

Single exported function `_graphify_maybe_prompt "$target"`. Called at the end of `cmd_init`, just before the "Next step: activate" banner.

**Behaviour:**

- If `graphify` is not on PATH: print a one-line tip pointing to `uv tool install graphifyy`. Return 0.
- If `graphify` is on PATH: print `● Graphify detected — build a knowledge graph now? [y/N]`.
  - Answer N (or empty): return 0.
  - Answer Y: run `graphify .` piped through `sed 's/^/  /'` for indented output. On success, move `graphify-out/` → `$target/.platform/graphify/` and print a confirmation. On non-zero exit, print a yellow warning and continue.

**Output location:** `.platform/graphify/` — already covered by the agentboard runtime `.gitignore` block since `.platform/` is ignored.

**Note on `--output-dir`:** graphify (PyPI: `graphifyy`) outputs to `graphify-out/` with no documented `--output-dir` flag. The implementation moves the directory post-run. If a future graphify version adds the flag, the implementation can be simplified to pass it directly.

**File size:** This file must stay under 300 lines. `init.sh` is frozen at 348 — the call is a single line replacing one blank line (net 0 growth).

---

## Component 2: `templates/skills/ab-graphify/SKILL.md`

Provider-agnostic skill. Uses `graphify .` shell syntax (not `/graphify`) so it works identically in Claude Code, Codex, and Gemini CLI.

**Content sections:**

1. **What it is** — graphify scans the project and writes three files to `.platform/graphify/`: `graph.html` (interactive browser viz), `GRAPH_REPORT.md` (key concepts, cross-cutting patterns, suggested questions), `graph.json` (full queryable graph).

2. **When to suggest it**
   - At `ab init` time if the CLI prompt was skipped or graphify was installed after init
   - After `ab rescan` on a codebase with ≥5 files changed
   - Before starting a new stream that touches unfamiliar parts of the repo

3. **How to invoke** — run via the shell tool:
   ```bash
   graphify .
   ```
   Output lands in `.platform/graphify/` (moved from `graphify-out/` post-run if needed).

4. **How to use the output** — during `ab-research`, read `.platform/graphify/GRAPH_REPORT.md` first. It surfaces cross-cutting patterns and surprising connections that grep misses. Reference `graph.json` for precise dependency queries.

5. **Install reminder** — if `graphify` is not found:
   ```bash
   uv tool install graphifyy && graphify install
   ```

**Deployment:** `ab update` copies `templates/skills/ab-graphify/` to `.claude/skills/ab-graphify/`, `.agents/skills/ab-graphify/`, and `.codex/skills/ab-graphify/` in any project that already has those directories.

---

## Component 3: Activation template updates (all three providers)

**Files:** `CLAUDE.md.template`, `AGENTS.md.template`, `GEMINI.md.template`

**Change 1 — skills list:** Append `ab-graphify` to the `## Skills available to you` section in each template.

**Change 2 — activation protocol:** In the activation checklist (the steps the LLM follows when the user says "activate this project"), add one optional step:

> **Optional — knowledge graph:** If `graphify --version` returns a version number, run `graphify .` via your shell tool to build `.platform/graphify/GRAPH_REPORT.md`. Takes ~30 seconds. Skip if graphify is not installed — suggest `uv tool install graphifyy` instead.

This step is identical across all three templates so Gemini, Codex, and Claude Code all surface the same suggestion at activation time.

---

## Constraints honoured

| Rule | How |
|---|---|
| No required deps | `_graphify_maybe_prompt` returns 0 on every path; graphify absent = tip only |
| `init.sh` frozen at 348 lines | New logic in separate file; call replaces a blank line |
| New bash files < 300 lines | `graphify_prompt.sh` is ~50 lines |
| Stack-agnostic verbatim files | Skill uses no stack references; activation step is two lines |
| Provider parity | Identical skill content and activation step in all three templates |

---

## Testing

- `tests/unit/file_size_ratchet_test.sh` — must pass (init.sh must not grow past 348)
- New unit test `tests/unit/graphify_prompt_test.sh`:
  - graphify absent → tip printed, no prompt, exit 0
  - graphify present, answer N → no graphify run, exit 0
  - graphify present, answer Y, graphify succeeds → `.platform/graphify/` created, confirmation printed
  - graphify present, answer Y, graphify exits non-zero → warning printed, exit 0 (never fail init)
- `templates/skills/ab-graphify/SKILL.md` presence verified by `ab update` skill-sync smoke test

---

## What is not in scope

- `ab update` does not backfill graphify into existing projects' activation templates (CLAUDE.md / AGENTS.md / GEMINI.md) — those are user-owned files after first activation.
- No `ab graphify` standalone command — on-demand use is handled by the skill.
- No automatic re-run on `ab rescan` — the skill instructs the LLM to suggest it; the user decides.
