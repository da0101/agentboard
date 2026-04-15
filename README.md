# Agentboard

**A starter kit that gives Claude Code, Codex CLI, and Gemini CLI a shared operating system for your project.**

```bash
cd /path/to/your/project
agentboard init
# then open the project in your AI CLI and say:
# > activate this project
```

Agentboard scaffolds a `.platform/` pack plus root entry files, then hands off to the LLM to scan the actual codebase, ask a few targeted questions, and write project-specific context. No stack picker. No static React/Django/Vite templates pretending to know your repo. The LLM reads the repo and decides.

> **Status:** actively evolving from a proven internal setup used across multi-repo product work. The kit is stack-agnostic; the project-specific intelligence is generated during activation.

---

## The problem

Every new AI session starts half-blind:

- The agent re-discovers decisions you already made
- The agent loads the wrong files and misses cross-layer constraints
- Parallel sessions collide because there is no shared task registry
- Useful context disappears when the session ends

Agentboard solves that by shipping a reusable **process layer** and leaving **project truth** to be written from your codebase during activation.

---

## What Agentboard actually is

Agentboard is not just a prompt stub. It gives a project:

- Root entry files: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
- A shared `.platform/` reference pack
- Workflow skills installed for multiple providers
- Workstream tracking that survives context loss
- Domain-first context files so agents load the right slice of the system
- Optional hub mode for multi-repo platforms

The design split is deliberate:

- **Generic, shipped verbatim:** workflow rules, onboarding path, sync script, work tracking protocol, repo templates, hooks
- **Project-specific, written during activation:** architecture, decisions, repos, domain files, conventions, current priorities

---

## Quick start

### Single repo

```bash
cd /path/to/project
agentboard init
```

Then open the repo in Claude Code, Codex CLI, or Gemini CLI and say:

```text
activate this project
```

### Multi-repo platform hub

If you run `agentboard init` in an empty parent folder or a folder that only contains sibling repos, Agentboard can switch to **hub mode**.

In hub mode:

1. `.platform/` lives in the hub folder
2. `.platform/repos.md` lists the sibling repos
3. `agentboard add-repo <path>` scaffolds thin entry files into each sibling repo
4. activation scans the sibling repos, not the hub folder itself

---

## What `agentboard init` does

`init` is intentionally small and generic. It does **not** make stack-specific decisions.

It:

1. Asks 2 questions: project name and one-line description
2. Copies the `.platform/` skeleton
3. Writes root entry stubs if they do not already exist
4. Preserves existing `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`
5. Installs shared skills into `.claude/skills/` and `.agents/skills/`
6. Installs `.claude/settings.json` if absent, so Claude Code can enforce closure hooks

If a root entry file already exists, `init` does not overwrite it. Activation later prepends the Agentboard section and preserves the original content below.

---

## What activation does

When you say `activate this project`, the root entry file tells the agent to read `.platform/ACTIVATE.md` or `.platform/ACTIVATE-HUB.md` and follow the activation protocol.

The activation flow is:

1. **Scan** the repo or sibling repos: tree, manifests, README, env examples, git history, source entry points
2. **Interview** the user with 5-8 targeted questions
3. **Fill** the project truth into the `.platform/` pack
4. **Install or merge** the steady-state root entry files without deleting user content
5. **Sync** `AGENTS.md` and `GEMINI.md` from `CLAUDE.md` where safe
6. **Confirm** what was written and what still needs review

The agent writes project-specific files from what it actually finds, including:

- `.platform/STATUS.md`
- `.platform/architecture.md`
- `.platform/decisions.md`
- `.platform/repos.md`
- `.platform/domains/*.md`
- `.platform/conventions/*.md`
- `.platform/work/BRIEF.md` when there is an active focus area

---

## Domain-first context

A key design choice is that feature context is **domain-first**, not repo-first.

Instead of forcing every agent to read:

- `backend.md`
- `frontend.md`
- `widget.md`

for one feature, activation creates focused files like:

- `.platform/domains/auth.md`
- `.platform/domains/orders.md`
- `.platform/domains/billing.md`

Each domain file is cross-layer. It can cover backend, frontend, widget, and API contract for that concern in one place. Repo-wide docs still exist, but they are for conventions and navigation, not feature briefings.

This keeps context small and makes multi-agent work much more reliable.

---

## Active work model

Agentboard ships a persistent work layer under `.platform/work/`:

- `BRIEF.md` — what the current active feature is, why it matters, what context to load
- `ACTIVE.md` — registry of live workstreams
- `TEMPLATE.md` — template for a new workstream
- `archive/` — completed workstreams

Streams and domains are meant to carry lightweight metadata so tooling can validate state without turning `.platform/` into a database.

The workflow expects non-trivial work to be registered before execution:

1. check `work/ACTIVE.md`
2. ensure a domain file exists
3. create `work/<stream>.md`
4. add the stream to `ACTIVE.md`
5. update `BRIEF.md`

This is what makes work resumable after context compaction or handoff to another agent.

---

## Skills

`agentboard init` installs a shared skill pack for all providers:

- `ab-triage`
- `ab-workflow`
- `ab-research`
- `ab-pm`
- `ab-architect`
- `ab-test-writer`
- `ab-security`
- `ab-qa`
- `ab-review`
- `ab-debug`

Install behavior is additive:

- Claude Code gets `.claude/skills/`
- Codex CLI and Gemini workflows get `.agents/skills/`
- existing skills with the same name are kept during `init`

Each skill has a `SKILL.md` and uses progressive disclosure: the name and description are visible at session start, and the full protocol loads on demand.

---

## What ships in the kit

```text
your-project/
├── CLAUDE.md
├── AGENTS.md
├── GEMINI.md
├── .claude/
│   └── settings.json
├── .agents/
│   └── skills/
└── .platform/
    ├── ACTIVATE.md / ACTIVATE-HUB.md
    ├── ONBOARDING.md
    ├── workflow.md
    ├── STATUS.md
    ├── architecture.md
    ├── decisions.md
    ├── repos.md
    ├── log.md
    ├── BACKLOG.md
    ├── learnings.md
    ├── agents/
    ├── domains/
    │   └── TEMPLATE.md
    ├── work/
    │   ├── BRIEF.md
    │   ├── ACTIVE.md
    │   ├── TEMPLATE.md
    │   └── archive/
    ├── sessions/
    │   └── ACTIVE.md
    ├── scripts/
    │   ├── sync-context.sh
    │   └── hooks/
    └── templates/
        └── repo/
```

After activation, the agent also creates project-specific directories and files such as:

- `.platform/conventions/*.md`
- `.platform/domains/*.md`
- `.platform/domains/TEMPLATE.md`
- per-repo deep references in hub mode

So the shipped scaffold is the operational shell; activation fills in the project-specific content.

---

## Commands

```bash
agentboard install
agentboard init
agentboard update [--dry-run]
agentboard sync [--apply|--list]
agentboard bootstrap [--apply-domains]
agentboard migrate [--apply]
agentboard brief-upgrade [stream-slug] [--apply]
agentboard doctor
agentboard new-domain <slug> [repo-id ...] [--repo <repo-id>]
agentboard new-stream <slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]
agentboard resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>
agentboard handoff [stream-slug]
agentboard claim "<task>"
agentboard release
agentboard log "<one line>"
agentboard status
agentboard add-repo <path>
agentboard version
agentboard help
```

### Command notes

- `install` creates a symlink for `agentboard` in your user bin directory and prints the PATH snippet to add if needed
- `init` scaffolds the kit into the current directory
- `update` refreshes shipped process files and skill protocols without touching project-specific docs
- `sync` keeps `AGENTS.md` and `GEMINI.md` aligned with `CLAUDE.md`
- `bootstrap` discovers repo layout, fills `repos.md`, scaffolds missing deep-reference files, infers starter domains from repo structure, suggests stream commands from git branch state, and syncs hub repo paths into `sync-context.sh`; use `--apply-domains` to create the inferred domain stubs
- `migrate` upgrades legacy pre-frontmatter stream/domain files to metadata v1 when Agentboard can infer the missing fields safely
- `brief-upgrade` rewrites a legacy multi-stream `work/BRIEF.md` into the newer single-stream format for one chosen stream
- `doctor` validates active `.platform/` state, stream/domain metadata, domain references, and repo IDs against the repo registry
- `new-domain` bootstraps a domain file with metadata and can assign multiple repo IDs up front
- `new-stream` bootstraps a stream file, registers it in `work/ACTIVE.md`, and seeds `work/BRIEF.md` when the brief is still a placeholder; repeat `--domain` and `--repo` when the stream spans multiple areas or repos
- `resolve` turns a canonical stream/domain/repo reference into the exact file or repo record to load
- `handoff` prints the minimum file load order, repo scope, and current-state summary another LLM needs to resume a stream without a full re-brief
- `claim` and `release` manage `.platform/sessions/ACTIVE.md`
- `log` appends to `.platform/log.md`
- `status` prints `.platform/STATUS.md`
- `add-repo` scaffolds entry files into a sibling repo in hub mode and refuses to overwrite existing root entry files

---

## Updating existing installs

As Agentboard evolves, `agentboard update` lets a project pull in newer process files without clobbering project truth.

For older projects that still use the legacy framework shape, use the dedicated migration flow in [MIGRATION_GUIDE.md](/Users/danilulmashev/Documents/GitHub/agentboard/MIGRATION_GUIDE.md).

It updates things like:

- `workflow.md`
- `ONBOARDING.md`
- `ACTIVATE*.md`
- `.platform/agents/*.md`
- shipped convention templates if the kit includes them
- `scripts/sync-context.sh`
- shipped skills

It does **not** overwrite project-authored operational state such as:

- `architecture.md`
- `decisions.md`
- `repos.md`
- `STATUS.md`
- `log.md`
- `work/*`
- `domains/*`

### Migrating older projects

If a project already has an older `.platform/` layout, the current upgrade path is:

```bash
agentboard update
agentboard migrate
agentboard migrate --apply
agentboard brief-upgrade <stream-slug> --apply
agentboard doctor
```

Use `brief-upgrade <stream-slug>` without `--apply` first if you want to preview the rewritten BRIEF before writing it.

The full step-by-step guide lives in [MIGRATION_GUIDE.md](/Users/danilulmashev/Documents/GitHub/agentboard/MIGRATION_GUIDE.md).

---

## Single repo vs hub mode

### Single repo

- `.platform/` lives beside the app code
- activation scans the current repo
- `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` live at the repo root

### Hub mode

- the hub folder holds `.platform/` and shared cross-repo truth
- sibling repos get thin entry stubs
- activation scans all listed sibling repos
- per-repo deep references can point agents back into the shared platform pack

Hub mode is useful when your system is split across backend, frontend, mobile, widget, or infra repos but you still want one shared context brain.

---

## Why no stack pre-picking

Traditional scaffolding asks: React or Vue? Django or FastAPI? Postgres or MongoDB?

Agentboard does not, for three reasons:

1. The stack is already visible in the repo
2. Static stack templates go stale quickly
3. The LLM can write rules for the actual project, not generic best practice

The point of the kit is to scaffold the **structure** and let activation generate the **truth**.

---

## Install

```bash
git clone https://github.com/[you]/agentboard ~/code/agentboard
~/code/agentboard/bin/agentboard install
```

By default, `agentboard install` symlinks into your user bin directory such as `~/.local/bin/agentboard` and tells you what to add to your shell config if that directory is not already on your `PATH`.

You can also preview or override the target:

```bash
~/code/agentboard/bin/agentboard install --dry-run
~/code/agentboard/bin/agentboard install --dir ~/bin
```

---

## License

MIT
