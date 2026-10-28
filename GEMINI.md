<!-- agentboard:root-entry:begin v=1 -->
# Agentboard — the tool itself

> **Activated on this repo (dogfooded).** `.platform/` tracks our own streams, memory and knowledge cards; only runtime files (events, locks, daemon port) are gitignored.

**What this is:** a starter kit that scaffolds a `.platform/` AI-agent context pack into any project, then hands off to an LLM to fill it from the real codebase. No stack pre-picking, no static convention templates — the LLM decides. **This repo is the TOOL, not a project.**

## Repo map

| Path | What |
|---|---|
| `bin/ab`, `bin/agentboard` | entry points. They must source and dispatch the same commands (`entry_points_parity_test`). |
| `lib/agentboard/core/` | shared helpers (`base.sh`, `frontmatter.sh`, `project_state.sh`, …) |
| `lib/agentboard/commands/` | one file per command (`ab help`). New command → new file, register in **both** entry points. |
| `templates/platform/` | copied into `<project>/.platform/` by `init`. Verbatim: `workflow.md`, `ACTIVATE*.md`, `protocols/`, `kernel/` (rules agents always load — keep tiny), `roles/`, `routing.tsv`, `models.tsv`. Placeholders: `STATUS.md`, `architecture.md`, `repos.md`, `memory/*`. `conventions/` stays EMPTY — the LLM writes it. |
| `templates/root/` | entry-file stubs. Their kernel block is generated: change `templates/platform/kernel/*.md`, then `ab entry build-templates` (a test fails if stale). |
| `templates/skills/`, `templates/skills-extra/` | 12 core skills installed by `init`; the rest are opt-in (`ab skill install`). Each installed skill costs prompt tokens every session. |
| `extensions/vscode/` | VS Code extension — **paused**, do not work on it. |
| `tests/` | `unit.sh [--filter X]` (full run ≈ 18 min), `integration.sh`. |

## The activation contract

`ab init` makes **no** project-specific decisions: it copies the skeleton, asks only project name + one-line description, and drops a stub. Stack detection, architecture, conventions, decisions and status are written by the LLM during activation, from the user's actual code. That keeps the kit tiny and generic and works for any stack. `templates/platform/ACTIVATE.md` and the stubs are the most important files in the repo.

## Hard rules

0. **Think like a best-in-class Silicon Valley product team** — and turn ambition into scoped slices, explicit tradeoffs, tests, rollback thinking and human approval for scope changes.
1. **Never add stack pre-picking to `ab init`.** The LLM decides the stack during activation.
2. **Never ship a static `conventions/{stack}.md`.** The LLM writes those per project.
3. **Verbatim templates must be stack-agnostic** — no React / Django / Unity examples baked in.
4. **Placeholders are `{{UPPERCASE_SNAKE}}`; `init` fills only `{{PROJECT_NAME}}`, `{{DESCRIPTION}}`, `{{TODAY}}`.** Everything else is filled during activation.
5. **Bash must stay portable** (macOS default bash 3.2): no bash-4-only features, no GNU-only flags. Traps: `local -a x` (write `=()`), `head -N` (the CLI defines its own `head()` — use `awk 'NR<=N'`), `grep` with no match inside `$(…)` under `set -e`.
6. **No required runtime dependencies.** Core commands are pure bash + file I/O. Opt-in extras fail gracefully when missing: `usage` needs `sqlite3`, the Claude closure gate needs `node`, `watch --install` needs `launchctl`/`schtasks`.
7. **Max 300 lines per bash file** in `lib/` and `bin/` (`file_size_ratchet_test`). Split, never grow; never add ratchet allowlist entries. Applies to code, not docs.
8. **Tests never touch the real home.** Shared helpers give every test file a throwaway `HOME`; keep it that way.

## Working on this repo

Plans live in chat, never in `.md` files. Every successful task appends one line to `.platform/memory/log.md`. For a new stream: research first, present the plan, wait for approval (`ab protocol new-task`). Branch in the main checkout; a worktree only on demand (`ab worktree new`). Iterate with `tests/unit.sh --filter <name>`; run the full suite before committing.


<!-- agentboard:kernel:begin v=1 -->
## Agentboard

Shared work-state for Claude Code, Codex and Gemini. Long procedures are on demand — `ab protocol` lists them, `ab protocol <name>` prints one.

**Session start:** run `ab brief --start`. One open stream → resume it (`ab handoff <slug>`); several → ask which; none → ask what to work on.

**Loading:** open only files named in `work/BRIEF.md` § "Relevant context". For a feature or topic run `ab recall <topic> [--layer backend|web|mobile]` before opening a domain file. Never read `work/archive/*`.

**Hard rules**
1. Task not in `work/ACTIVE.md`? Run `ab protocol new-task` before any research or code. New stream: research first, present the plan, wait for human approval.
2. Work on a `feature/<slug>` or `bugfix/<slug>` branch in the main checkout (`hotfix/<slug>` only if told). Worktrees are on demand: `ab worktree new <slug>`.
3. Only the human closes a stream (`ab protocol closure`). Record durable facts in the stream's `## Knowledge delta` as you work.
4. Change needs human or app-driving verification? `ab protocol qa` before any commit, push, merge or release.
5. Ending, low on context, or switching provider: `ab checkpoint <slug> --what "…" --next "…"` (`ab protocol handoff`).
6. After an edit another agent must understand: `ab log-reason "<why>"` (`ab protocol reasoning`).
7. **Role activation:** on the first task message match its intent to a role in `.platform/roles/INDEX.md` and adopt it; no confident match → `pair-programmer`, silently (`ab protocol roles`).
8. Audit or analysis of a stream: `ab protocol audit`.
9. User says "update the platform", "rescan" or "you're out of date": run `ab rescan`, then follow `.platform/RESCAN.md`.

**Silicon Valley product mindset:** act like best-in-class Silicon Valley product teams — user-obsessed, craft-driven, fast, rigorous — never as permission for scope creep, weak tests or skipping approval gates (`.platform/workflow.md`).

**Gemini CLI:** there is no hook system, so the closure and QA gates rely on you following rules 3–4. On long sessions the user can run `ab watch &` to auto-checkpoint.
<!-- agentboard:kernel:end v=1 -->
<!-- agentboard:root-entry:end v=1 -->
