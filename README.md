# Agentboard

**A two-command starter kit that gives every AI coding agent an instant "brain" for your project.**

```bash
cd /path/to/your/project
agentboard init          # scaffold a .platform/ skeleton + drop an activation prompt
# then open the project in Claude Code / Codex CLI / Gemini CLI and say:
# > activate this project
```

The LLM scans your actual codebase (manifests, directory tree, README, git log), asks you 5–8 targeted questions, and fills in the context pack **based on what it finds** — not on a pre-picked stack list. Works for Django, React, Next.js, Unity, Unreal, Xcode, Android Studio, Flutter, Rust, Go, C++, Godot, or anything else. **The LLM decides.**

> **Status:** blueprint extracted from the RestoHub platform (4 repos, 2026-04-10). Generic, stack-agnostic, and designed for the LLM to do the project-specific work.

---

## The problem

Every new AI session starts blind. Without a context setup:
- The agent re-researches decisions already made
- The agent writes code that contradicts existing architecture
- You spend the first 20 minutes re-explaining the project
- Bugs happen because the agent didn't know a constraint

Agentboard solves this by dropping a structured `.platform/` context layer next to your code and then **handing off to the LLM itself** to fill that layer in from your actual codebase. No wizard asking "which stack?" No static convention templates you have to adapt. The LLM looks at your code and writes the rules that apply to THAT code.

---

## How activation works

### 1. Run `agentboard init`

Two questions (project name, one-line description). That's it. Agentboard copies the skeleton into `.platform/` and drops an activation-mode `CLAUDE.md` at your project root.

### 2. Open your project in an AI CLI

Claude Code, Codex CLI, or Gemini CLI — any of them. The CLI auto-loads `CLAUDE.md` (or `AGENTS.md` / `GEMINI.md` — all three are synced), which is now the activation prompt.

### 3. Say "activate this project"

The LLM runs a 6-step activation protocol:

1. **Scan** — reads your directory tree, manifest files (`package.json`, `pyproject.toml`, `Cargo.toml`, `Podfile`, `build.gradle`, `*.csproj`, `CMakeLists.txt`, etc.), README, env-example files, git history. Identifies languages, frameworks, build tools, external services.
2. **Interview** — asks 5–8 targeted questions to fill the gaps the scan couldn't answer (what the project does, hard constraints, external services, single vs multi-repo, known gotchas, top priority).
3. **Fill** — generates `.platform/STATUS.md`, `architecture.md`, `decisions.md`, `repos.md`, and a set of `conventions/{stack}.md` files — **one for each stack it detected**, with rules tailored to your actual codebase.
4. **Replace** — rewrites `CLAUDE.md` from activation-mode into a lean ~100-line steady-state entry point.
5. **Sync** — runs `sync-context.sh --apply` to generate `AGENTS.md` and `GEMINI.md` from the new `CLAUDE.md`.
6. **Confirm** — shows a summary of what was filled, what was left as TODOs, and what it recommends as the next task.

Your project is now activated. Every future session (any agent, any CLI) auto-loads the new `CLAUDE.md` and is immediately productive.

---

## Skills (installed additively into `.claude/skills/`)

`agentboard init` also installs a curated set of workflow skills for Claude Code. They are **additive** — any pre-existing skills in `.claude/skills/` are never overwritten. All skills are prefixed `ab-` to avoid colliding with gstack or other skill packs.

| Skill | Purpose |
|---|---|
| `ab-triage` | Classify task (type/scope/risk) before starting work. Gate for everything else. |
| `ab-workflow` | 6-stage inline workflow orchestrator (triage → interview → research → propose → execute → verify). |
| `ab-research` | Bounded research (1 search + 3 fetches + 5 reads) with ≤300-word synthesis in chat. |
| `ab-pm` | Product thinking — user value, simplest validation, failure modes, BUILD/RESHAPE/KILL verdict. |
| `ab-architect` | System/component design with invariants, data flow, failure modes, cross-cutting concerns. |
| `ab-test-writer` | Unit test writer with edge-case enumeration per feature type (API / logic / auth / mutation / UI). |
| `ab-security` | OWASP-aligned audit: auth, authorization, secrets, injection, tenant isolation, logging hygiene. |
| `ab-qa` | Real-browser/manual QA with acceptance criteria + 6 edge-case buckets + reproducible findings. |
| `ab-review` | Pre-PR code review on 4 axes: spec compliance, quality, security, test coverage. |
| `ab-debug` | Root-cause investigation via hypothesis-test-narrow loop (max 3 hypotheses before re-assess). |

Each skill has a detailed `SKILL.md` with protocol, hard rules, red flags, and anti-patterns. Read them once when you first adopt the kit.

## What ships in the kit

```
your-project/
├── CLAUDE.md              ← activation prompt on first run, steady-state entry after activation
├── AGENTS.md              ← generated from CLAUDE.md by sync
├── GEMINI.md              ← generated from CLAUDE.md by sync
│
└── .platform/
    ├── ONBOARDING.md          ← verbatim — 7-step reading path
    ├── workflow.md            ← verbatim — 6-stage inline workflow
    ├── STATUS.md              ← skeletal — LLM fills during activation
    ├── architecture.md        ← skeletal — LLM fills during activation
    ├── decisions.md           ← skeletal — LLM fills during activation
    ├── repos.md               ← skeletal — LLM fills during activation
    ├── log.md                 ← skeletal — LLM appends its first "activated" line
    │
    ├── conventions/           ← empty — LLM creates files based on detected stack
    │
    ├── templates/repo/        ← verbatim — used later for `add-repo` command
    │   ├── ADDING-A-REPO.md
    │   ├── CLAUDE.md.template
    │   ├── AGENTS.md.template
    │   ├── GEMINI.md.template
    │   ├── STATUS.md.template
    │   └── reference.md.template
    │
    ├── scripts/
    │   └── sync-context.sh    ← verbatim — keeps entry files in lockstep
    │
    └── sessions/
        └── ACTIVE.md          ← verbatim — parallel-session coordination (multi-repo)
```

**Key idea:** the kit ships the **generic plumbing** verbatim (workflow, onboarding path, sync script, per-repo scaffold, session coordination, log format) and leaves everything **project-specific** for the LLM to write during activation.

---

## Install

```bash
git clone https://github.com/[you]/agentboard ~/code/agentboard
ln -sf ~/code/agentboard/bin/agentboard /usr/local/bin/agentboard
```

Or copy `bin/agentboard` anywhere on your `$PATH`.

---

## Commands

```bash
agentboard init                    # scaffold .platform/ + drop activation prompt
agentboard sync                    # check AGENTS.md + GEMINI.md drift from CLAUDE.md
agentboard sync --apply            # regenerate drifted files
agentboard claim "<task>"          # add row to .platform/sessions/ACTIVE.md
agentboard release                 # remove your row
agentboard log "<one line>"        # append timestamped line to .platform/log.md
agentboard status                  # print .platform/STATUS.md
agentboard add-repo <path>         # copy per-repo entry templates to a new sibling repo
agentboard help                    # show help
```

---

## Why no stack pre-picking?

Traditional scaffolding tools ask "React or Vue? Django or FastAPI? MongoDB or Postgres?" Agentboard doesn't. Three reasons:

1. **The LLM can look.** `package.json`, `pyproject.toml`, `build.gradle`, `*.xcodeproj`, `CMakeLists.txt` — the stack is already in the repo. The LLM reads it in 10 seconds.
2. **Static convention templates go stale.** A pre-shipped `conventions/react.md` would assume React 18, class-based vs hooks, Redux vs Zustand, Vite vs Next. Your project has already made those choices. Let the LLM read your actual code and write the rules **that apply to your code**, not generic best practices.
3. **Works for any stack.** Agentboard has never heard of your stack? Doesn't matter. The LLM knows what Unity, Godot, SwiftUI, Jetpack Compose, Tauri, Deno, or whatever-you're-using looks like. It'll write a conventions file.

---

## Parallel AI sessions

`sessions/ACTIVE.md` is a shared claims table for when Claude Code + Codex CLI + Gemini CLI are all running on the same project:

```markdown
| start_time       | agent        | repo             | area              | task_summary           | eta     | status |
|------------------|--------------|------------------|-------------------|------------------------|---------|--------|
| 2026-04-10 21:30 | claude-code  | my-backend       | auth/             | add token refresh      | ~30min  | active |
| 2026-04-10 21:32 | codex-cli    | my-frontend      | src/login/        | wire refresh UX        | ~15min  | active |
```

**Collision rules:**
- **Hard collision** (same file) → second session stops, negotiates
- **Soft collision** (same repo, different files) → allowed, commit frequently
- **Cross-repo** → allowed freely

---

## Single-repo vs multi-repo

Agentboard doesn't care. During activation, the LLM asks "is this a single-repo project or does it coordinate with siblings?" and adapts:

- **Single-repo:** `.platform/` lives next to your code. `sessions/ACTIVE.md` and `templates/repo/` are still present but optional.
- **Multi-repo:** `.platform/` lives in a "platform" repo that's a sibling to your working repos. Each working repo gets a lean `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` that points into the platform pack. `sync-context.sh` keeps them all in lockstep.

---

## What stays generic (ships verbatim)

These files ship in every project and never need editing for project-specific content:

| File | Why |
|---|---|
| `workflow.md` | The 6-stage inline workflow applies to every project |
| `ONBOARDING.md` | The 7-step reading path applies to every project |
| `sync-context.sh` | Generic sed-based sync; only the `REPOS=()` array is edited per-project |
| `sessions/ACTIVE.md` | Generic claims table format |
| `templates/repo/*` | Generic per-repo scaffold for adding new repos later |
| `log.md` format | `YYYY-MM-DD — <task> — <outcome> — <takeaway>` |

---

## What gets written per-project (by the LLM during activation)

| File | Who writes it |
|---|---|
| `CLAUDE.md` (steady-state) | LLM, after reading your codebase |
| `STATUS.md` | LLM, from scan + interview |
| `architecture.md` | LLM, from scan + interview |
| `decisions.md` | LLM, from scan (seeds 3–5 initial decisions) |
| `repos.md` | LLM, from directory scan |
| `conventions/{stack}.md` | LLM, one per detected stack, rules match YOUR code |
| `conventions/{cross-cutting}.md` | LLM, only for areas that apply to your project |

---

## License

MIT
