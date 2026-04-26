# Agentboard — Architecture

Last updated: 2026-04-18

## One-line purpose

A bash CLI that scaffolds and maintains a `.platform/` directory in any project so Claude Code, Codex CLI, and Gemini CLI can share structured work-state via files, plus an optional local Node daemon for event serialization and file-lock coordination.

## Design principles (non-negotiable)

1. **Pure bash.** BSD-compatible (macOS bash 3.2). No bash 4+ features.
2. **Zero required runtime dependencies.** Core workflows stay bash-only. An optional local Node daemon is used for event serialization and file-lock coordination when available. `sqlite3` is optional (usage tracking only).
3. **File-based state.** Markdown + YAML frontmatter is the source of truth. CLI reads and writes these files.
4. **Stack-agnostic.** The tool never pre-picks a framework. The LLM decides during activation by reading the user's actual code.
5. **~300 lines per bash file.** Stated rule; currently violated in a few files (tracked in STATUS.md).

## Component boundaries

```
bin/agentboard                  ← thin dispatcher; sources all command files
lib/agentboard/
  core.sh                       ← sources core/*.sh in order
  core/
    base.sh                     ← color output, frontmatter helpers, path utils
    project_state.sh            ← stream_files, frontmatter_value, render helpers
    project_detection.sh        ← detect repo stack, active stream, hub mode
    bootstrap_repos.sh          ← discover sibling repos (hub mode)
    bootstrap_domains.sh        ← infer starter domains from repo layout
  commands/
    init.sh, update.sh, migrate_layout.sh, migration.sh, bootstrap.sh
    doctor.sh, streams.sh, progress.sh
    checkpoint.sh, close.sh, brief.sh, watch.sh
    daemon.sh, events.sh, lock.sh
    install_hooks.sh, usage.sh, session.sh, system_setup.sh, help.sh
templates/
  platform/        ← copied into target project's .platform/ by init
    memory/        ← decisions, learnings, log, gotchas, playbook, open-questions, BACKLOG
    work/          ← TEMPLATE.md, ACTIVE.md, BRIEF.md, archive/
    domains/       ← per-domain context files (LLM-written)
    conventions/   ← per-stack rules (LLM-written, empty at init)
    agents/        ← protocol reminders (verbatim)
    scripts/       ← sync-context.sh, codex-ab, gemini-ab, session-track.sh, hooks/
  root/            ← CLAUDE.md / AGENTS.md / GEMINI.md templates
  skills/          ← 10 ab-* skills installed to .claude/skills and .agents/skills
```

## Data flow

**Scaffolding → activation**
1. `agentboard init` copies `templates/platform/*` verbatim + substitutes name/description.
2. LLM opens project, auto-loads CLAUDE.md/AGENTS.md/GEMINI.md entry file.
3. User: "activate this project." LLM reads `.platform/ACTIVATE.md`, fills architecture/decisions/domains/conventions.

**Work session (steady state)**
1. Session start: `agentboard brief` → active streams, recent gotchas, open questions, usage pattern.
2. Resume: `agentboard handoff <slug>` → load order + Resume state block.
3. Segment boundary: `agentboard checkpoint <slug> --what … --next … [--cumulative-in N --cumulative-out N --provider X --model Y]`.
4. Optional: wrappers auto-start the daemon and session tracking; Claude hooks use the daemon-backed lock queue when available.
5. Optional: `agentboard watch &` polls git every 10 min, auto-checkpoints when files change (multi-stream since v1.5.1).
6. Stream complete: `agentboard close <slug>` prints harvest checklist → LLM distills into memory/*.md → `close <slug> --confirm` archives + runs `usage learn --apply`.

**Accumulation loop (the "20-year employee")**
Each closed stream appends durable lines to memory/*.md. Next agent's `brief` surfaces them. Over N streams, project-specific wisdom compounds without the user re-explaining.

## Enforcement layers

| Layer | Mechanism | Scope |
|---|---|---|
| Honor system | Entry-template instructions + markdown prompts | All 3 CLIs |
| Staleness warnings | `handoff` flags Resume state > 1 day old | All 3 CLIs |
| Closure gate hook | Blocks Edit on ACTIVE.md that removes a row without `closure_approved: true` | Claude Code only |
| Bash guard hook | PreToolUse `ask` on destructive git / rm -rf / force-push | Claude Code only |
| SessionStart hook | Runs `platform-bootstrap.sh` | Claude Code only |
| Lock queue | Optional daemon-backed file locks; Claude enforced by hooks, Codex/Gemini via CLI + wrapper guidance | All 3 CLIs |

Codex/Gemini: honor system + staleness only. Hook enforcement is out of scope (no API).

## Failure modes (by design)

- Agent forgets to checkpoint → next `handoff` shows stale data; `brief` still surfaces memory.
- Agent forgets to harvest before `close --confirm` → lessons lost; `close` warns loudly.
- Watch not started → state stale during long Codex/Gemini sessions. Mitigation planned: v1.6 Phase 2 (`watch --install`).
- Token counts not passed → checkpoint still succeeds; usage row skipped silently. `learn` has less data.

## Testing

- `tests/unit/*_test.sh` — ~30 files, run via `tests/unit.sh`
- `tests/integration.sh` — end-to-end init/bootstrap flows
- CI: GitHub Actions on ubuntu-latest (bash 5). Local dev: macOS bash 3.2. Cross-version bugs tracked in `memory/gotchas.md`.

## Release process

1. Branch `feature/...` off `develop`
2. PR → admin-merge to `develop`
3. Accumulate features on `develop`
4. Bump VERSION on a `chore/vN.N.N-bump` PR
5. Release PR `develop` → `main`
6. Tag `vN.N.N` on `main` after merge
7. Auto-release workflow publishes GitHub Release; edit notes post-hoc
