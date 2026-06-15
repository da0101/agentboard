<!-- agentboard installed + activated 2026-04-17 -->
> **agentboard is activated** on this repo. We dogfood agentboard on itself — `.platform/` tracks our live streams, checkpoints, and accumulated memory. Run `agentboard brief` at session start. The `.platform/` dir is gitignored; only the kit itself is committed.

---

# Agentboard — the tool itself

**What this is:** A starter kit that scaffolds a `.platform/` AI-agent context pack into any project, then hands off to an LLM to fill the pack from the actual codebase. No stack pre-picking. No static convention templates. The LLM decides.

**This repo is the TOOL, not a project.** When users run `agentboard init`, they get the skeleton. When they then say "activate this project" to Claude Code / Codex / Gemini, the LLM scans their code and fills the skeleton.

## Repo structure

```
agentboard/
├── README.md              ← user-facing docs
├── CLAUDE.md              ← this file — rules for working on agentboard itself
├── CHEATSHEET.md          ← command reference
├── MIGRATION_GUIDE.md     ← upgrade path for older layouts
├── CONTRIBUTING.md
├── LICENSE
├── bin/
│   └── agentboard         ← entry point; delegates to lib/
├── lib/agentboard/
│   ├── core.sh            ← library loader
│   ├── core/
│   │   ├── base.sh            (shared utilities, colors, die/ok helpers)
│   │   ├── project_state.sh   (reads .platform/ state)
│   │   ├── project_render.sh  (renders briefs, repo references, registry tables)
│   │   ├── project_detection.sh
│   │   ├── bootstrap_repos.sh
│   │   └── bootstrap_domains.sh
│   └── commands/
│       ├── init.sh / install.sh / update.sh
│       ├── streams.sh         (new-stream, new-domain)
│       ├── stream_resolve.sh  (resolve, current-stream, next-action)
│       ├── handoff.sh / handoff_render.sh  (handoff packet)
│       ├── checkpoint.sh / progress.sh / close.sh
│       ├── usage.sh           (log, summary, dashboard, learn — requires sqlite3)
│       ├── watch.sh / watch_poll.sh / watch_install.sh / watch_status.sh
│       │                      (git watcher — scheduler requires launchctl/schtasks)
│       ├── doctor.sh / bootstrap.sh / brief.sh
│       └── …
├── templates/
│   ├── platform/          ← copied into <project>/.platform/ by `init`
│   │   ├── ACTIVATE.md / ACTIVATE-HUB.md  (activation protocol)
│   │   ├── ONBOARDING.md      (verbatim)
│   │   ├── workflow.md        (verbatim)
│   │   ├── STATUS.md          (skeletal — placeholders)
│   │   ├── architecture.md    (skeletal — placeholders)
│   │   ├── repos.md / repos.hub.md
│   │   ├── memory/            (decisions, log, learnings, gotchas, playbook, open-questions, BACKLOG)
│   │   ├── agents/            (commands.md, context-organization.md, skill-labels.md, …)
│   │   ├── domains/TEMPLATE.md
│   │   ├── work/              (BRIEF.md, ACTIVE.md, TEMPLATE.md, archive/)
│   │   ├── conventions/       (EMPTY — LLM writes per-project)
│   │   ├── scripts/sync-context.sh (verbatim)
│   │   └── scripts/hooks/     (bash-guard.sh, platform-closure-gate.js, platform-bootstrap.sh)
│   ├── root/              ← root entry files dropped by `init`
│   │   ├── CLAUDE.md.template / CLAUDE.md.hub.template
│   │   ├── AGENTS.md.template
│   │   └── GEMINI.md.template
│   ├── skills/            ← ab-* skill pack installed into .claude/skills/
│   └── codex/             ← Codex agent configs
└── tests/
    ├── unit.sh
    ├── integration.sh
    └── helpers.sh
```

## The activation contract

The single most important design decision:

**`agentboard init` does NOT make project-specific decisions.** It only copies the skeleton + drops an activation-mode `CLAUDE.md`. All project-specific content (stack detection, architecture description, conventions, decisions, status) is written by the LLM during activation by reading the user's actual codebase and interviewing them briefly.

### Why this matters

- No stale static convention templates (`conventions/react.md` would always be wrong for someone's specific React setup).
- Works for any stack the LLM has knowledge of — Unity, Godot, Tauri, Deno, SwiftUI, Jetpack Compose, obscure DSLs — without the kit needing to know about that stack.
- Keeps the kit tiny and generic.
- The activation prompt (`templates/root/CLAUDE.md.template`) is the most important file in the repo. It's the instructions the LLM follows to do the activation.

### What ships verbatim vs what ships as placeholder

| File | Mode | Why |
|---|---|---|
| `workflow.md` | verbatim | 6-stage workflow is the same for every project |
| `ONBOARDING.md` | verbatim | Reading path is the same for every project |
| `sync-context.sh` | verbatim | Only `REPOS=()` array is per-project |
| `templates/repo/*` | verbatim | Generic per-repo scaffold |
| `scripts/hooks/*` | verbatim | Mechanical enforcement — not project-specific |
| `agents/*.md` | verbatim | Context-org and skill-label guides are universal |
| `STATUS.md` | placeholder | `{{PROJECT_NAME}}`, `{{DESCRIPTION}}`, `{{TODAY}}` |
| `architecture.md` | placeholder | Structure is generic, content is LLM-written |
| `memory/decisions.md` | placeholder | Structure is generic, content is LLM-written |
| `repos.md` | placeholder | Structure is generic, content is LLM-written |
| `memory/log.md` | placeholder | Just the header + first seeded line |
| `conventions/` | EMPTY | LLM writes one file per detected stack during activation |
| Root `CLAUDE.md.template` | special | The activation prompt itself — replaced post-activation |

## Working on agentboard

### When to edit `templates/root/CLAUDE.md.template`

- Changing the activation protocol (scan steps, interview questions, fill steps)
- Adding manifest files the LLM should look for
- Changing what the steady-state CLAUDE.md should look like after activation

### When to edit `templates/platform/workflow.md`

- Changing the 6-stage workflow
- Adding / removing hard rules
- Changing model profile recommendations

### When to edit `bin/agentboard` / `lib/agentboard/`

- New CLI subcommand → add `lib/agentboard/commands/<cmd>.sh`, register in `bin/agentboard`
- Core logic change → edit the relevant `lib/agentboard/core/*.sh` file
- Changing the init flow (don't add stack-picking, ever — that's explicitly rejected)
- Bug fix in any command → edit the corresponding `commands/*.sh` file

### Hard rules

0. **Think like a best-in-class Silicon Valley product team.** PMs, engineers,
   and all agent roles must be user-obsessed, future-facing, innovative,
   craft-driven, fast, and rigorous. Raise the bar beyond basic task
   completion, but convert ambition into scoped slices, explicit tradeoffs,
   maintainable implementation, tests, rollback thinking, and human approval
   for any scope change.
1. **Never add stack pre-picking to `agentboard init`.** The LLM decides the stack during activation. `init` only asks project name + one-line description.
2. **Never ship a static `conventions/{stack}.md` file.** The LLM writes those per-project, based on the user's actual code.
3. **Templates that ship verbatim** (`workflow.md`, `ONBOARDING.md`, `sync-context.sh`, `templates/repo/*`) must be **stack-agnostic**. No React / Django / Unity examples baked in.
4. **Placeholders use `{{UPPERCASE_SNAKE}}`.** The only three the `init` command fills are `{{PROJECT_NAME}}`, `{{DESCRIPTION}}`, `{{TODAY}}`. Everything else is filled by the LLM during activation.
5. **`sync-context.sh` must stay bash-portable.** macOS default shell must work. No bash 4-only features, no GNU-only flags.
6. **The CLI core has no required runtime dependencies.** `init`, `new-stream`, `new-domain`, `checkpoint`, `handoff`, `doctor`, and `sync` are pure bash + file I/O. The git pre-commit closure gate is also pure bash. Optional features are allowed opt-in system deps: `usage` commands require `sqlite3`; the Claude Code closure gate (`platform-closure-gate.js`) requires `node`; `watch --install` requires `launchctl` (macOS) or `schtasks` (Windows). Fail gracefully with a clear message when an optional dep is absent. Never add required deps.
7. **Max 300 lines per bash source file** in `lib/` and `bin/`, enforced by `tests/unit/file_size_ratchet_test.sh`. New bash files must come in under the cap — split them instead of growing them. A handful of legacy files already over the cap are frozen at their current recorded size by the ratchet test: they may shrink, but any growth fails the test suite. Never add new entries to the ratchet allowlist. This rule applies to executable code, not to documentation or workflow markdown — those are as long as they need to be.

## Workflow for editing this repo

Follow the 6-stage workflow in `templates/platform/workflow.md`:
1. Triage (type/scope/risk)
2. Interview (only if ambiguous)
3. Research (always for new streams; otherwise medium+ scope)
4. Propose inline in chat with phases, risks, mitigations, alternatives, tests, and rollback path
5. Execute
6. Verify + log

For new streams, research is mandatory even when the implementation looks small. Include targeted external research plus local context, then wait for human approval of the research-backed plan before implementation.

Before implementing any feature, bugfix, or hotfix stream, work from an isolated Git worktree per touched repo. Use `feature/<slug>` or `bugfix/<slug>` from `develop`; use `hotfix/<slug>` from `master` only when the user explicitly says hotfix. Install each repo's development dependencies in its worktree, identify the local dev command and localhost port(s), and record them in the stream file before coding or QA.

Before any commit, push, merge, release, or stream closure for implementation, bug fix, debugging, feature, UI, API behavior, or release work that requires human/app-driving verification, create a durable QA markdown document at `.platform/work/qa/<stream-slug>-manual-qa.md`. Cover scope, environment, test data, safety limits, exact click/type/navigation steps, expected results, happy path, bug repro/regression steps, edge cases, browser/device checks when relevant, accessibility checks when relevant, evidence to capture, Maestro/automation notes when relevant, and pass/fail signoff. If manual QA is not relevant, record `Manual QA: not required — <specific reason>` in the stream file and explain why. Do not delete QA docs; archive them with the stream under `.platform/work/archive/qa/`.

**QA execution journal rule.** When an LLM/agent uses Maestro, Browser, Playwright, MCP, a simulator/emulator, or another interactive tool to drive the app, also create `.platform/work/qa/<stream-slug>-execution-journal.md`. Document every meaningful step from the agent perspective: tool used, action, observation, expected result, actual result, pass/fail/skipped status, evidence, bugs found, diagnosis, fix or human escalation, retest, successful paths, blockers, and remaining risk. Do not replace this with a final summary; the journal is the chronological trace.

Plans live in chat, not `.md` files. Every successful task appends one line to `.platform/memory/log.md` (this repo dogfoods agentboard — `.platform/` is gitignored but populated locally, so we eat our own dogfood and get real usage data).

## Reference implementation

The full setup this kit generates was battle-tested on the **RestoHub platform** (4-repo Django + React SaaS). Source: `/Users/danilulmashev/Documents/GitHub/restohub-platform/.platform/`. That's where the workflow, sync script, and per-repo scaffold were proven. The activation-prompt model is a generalization of that learning.
