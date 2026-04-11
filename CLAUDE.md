# Agentboard — the tool itself

**What this is:** A starter kit that scaffolds a `.platform/` AI-agent context pack into any project, then hands off to an LLM to fill the pack from the actual codebase. No stack pre-picking. No static convention templates. The LLM decides.

**This repo is the TOOL, not a project.** When users run `agentboard init`, they get the skeleton. When they then say "activate this project" to Claude Code / Codex / Gemini, the LLM scans their code and fills the skeleton.

## Repo structure

```
agentboard/
├── README.md              ← user-facing docs
├── CLAUDE.md              ← this file — rules for working on agentboard itself
├── LICENSE                ← MIT
├── bin/
│   └── agentboard         ← bash CLI (init / sync / claim / release / log / status / add-repo)
└── templates/
    ├── platform/          ← copied into <project>/.platform/ by `init`
    │   ├── ONBOARDING.md      (verbatim)
    │   ├── workflow.md        (verbatim)
    │   ├── STATUS.md          (skeletal — placeholders)
    │   ├── architecture.md    (skeletal — placeholders)
    │   ├── decisions.md       (skeletal — placeholders)
    │   ├── repos.md           (skeletal — placeholders)
    │   ├── log.md             (skeletal — placeholders)
    │   ├── conventions/       (EMPTY — LLM writes per-project)
    │   ├── templates/repo/    (verbatim — per-repo scaffold)
    │   ├── scripts/sync-context.sh (verbatim)
    │   └── sessions/ACTIVE.md (verbatim)
    └── root/
        └── CLAUDE.md.template ← activation prompt dropped at project root by `init`
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
| `sessions/ACTIVE.md` | verbatim | Generic claims table format |
| `templates/repo/*` | verbatim | Generic per-repo scaffold |
| `STATUS.md` | placeholder | `{{PROJECT_NAME}}`, `{{DESCRIPTION}}`, `{{TODAY}}` |
| `architecture.md` | placeholder | Structure is generic, content is LLM-written |
| `decisions.md` | placeholder | Structure is generic, content is LLM-written |
| `repos.md` | placeholder | Structure is generic, content is LLM-written |
| `log.md` | placeholder | Just the header + first seeded line |
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

### When to edit `bin/agentboard`

- New CLI subcommand
- Changing the init flow (don't add stack-picking, ever — that's explicitly rejected)
- Bug fix in sync / claim / release / log / add-repo

### Hard rules

1. **Never add stack pre-picking to `agentboard init`.** The LLM decides the stack during activation. `init` only asks project name + one-line description.
2. **Never ship a static `conventions/{stack}.md` file.** The LLM writes those per-project, based on the user's actual code.
3. **Templates that ship verbatim** (`workflow.md`, `ONBOARDING.md`, `sync-context.sh`, `sessions/ACTIVE.md`, `templates/repo/*`) must be **stack-agnostic**. No React / Django / Unity examples baked in.
4. **Placeholders use `{{UPPERCASE_SNAKE}}`.** The only three the `init` command fills are `{{PROJECT_NAME}}`, `{{DESCRIPTION}}`, `{{TODAY}}`. Everything else is filled by the LLM during activation.
5. **`sync-context.sh` must stay bash-portable.** macOS default shell must work. No bash 4-only features, no GNU-only flags.
6. **No runtime dependencies.** Pure file-creation. No API calls, no npm install, no Python venv. If you want the LLM to do something, write it into the activation prompt — don't call an API from the CLI.
7. **Max ~300 lines per file** (ship the rule by following it).

## Workflow for editing this repo

Follow the 6-stage workflow in `templates/platform/workflow.md`:
1. Triage (type/scope/risk)
2. Interview (only if ambiguous)
3. Research (only if medium+ scope)
4. Propose inline in chat
5. Execute
6. Verify + log

Plans live in chat, not `.md` files. Every successful task appends one line to a mental log (this repo doesn't have its own `.platform/log.md` — it's the kit, not a project).

## Reference implementation

The full setup this kit generates was battle-tested on the **RestoHub platform** (4-repo Django + React SaaS). Source: `/Users/danilulmashev/Documents/GitHub/restohub-platform/.platform/`. That's where the workflow, sync script, and per-repo scaffold were proven. The activation-prompt model is a generalization of that learning.
