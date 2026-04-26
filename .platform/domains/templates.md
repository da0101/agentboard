---
domain_id: dom-templates
slug: templates
status: active
repo_ids: [repo-primary]
related_domain_slugs: [commands]
created_at: 2026-04-17
updated_at: 2026-04-17
---

# templates

## What this domain does

Every file `agentboard init` drops into a user project — the skeleton of `.platform/`, the root entry files (CLAUDE.md / AGENTS.md / GEMINI.md), the 10 `ab-*` skills, and `.codex/` subagent config. If it's copied into user projects, it's defined here.

## Layout

```
templates/
├── platform/                ← copied into <project>/.platform/ verbatim by init
│   ├── ACTIVATE.md              (6-step activation protocol; most important file)
│   ├── ACTIVATE-HUB.md          (hub-mode variant)
│   ├── ONBOARDING.md            (7-step session-start reading path)
│   ├── workflow.md              (6-stage inline workflow)
│   ├── STATUS.md                (placeholder — LLM fills at activation)
│   ├── architecture.md          (placeholder)
│   ├── repos.md                 (placeholder)
│   ├── memory/
│   │   ├── decisions.md, learnings.md, log.md
│   │   ├── gotchas.md, playbook.md, open-questions.md
│   │   └── BACKLOG.md
│   ├── work/                    TEMPLATE.md, ACTIVE.md, BRIEF.md, archive/
│   ├── domains/TEMPLATE.md      per-domain file template
│   ├── conventions/             EMPTY — LLM writes per-stack
│   ├── agents/                  protocol reminders (verbatim)
│   ├── scripts/
│   │   ├── sync-context.sh          (`REPOS=()` array is per-project)
│   │   └── hooks/
│   │       ├── platform-closure-gate.js     Claude Code PreToolUse Edit guard
│   │       ├── platform-bootstrap.sh        SessionStart hook
│   │       └── bash-guard.sh                Claude Code PreToolUse Bash guard (v1.6)
│   └── templates/repo/          per-repo scaffold for hub mode
├── root/                    ← copied to <project>/ root by init
│   ├── CLAUDE.md.template
│   ├── AGENTS.md.template
│   ├── GEMINI.md.template
│   └── .claude/settings.json    (pre-wired with closure-gate + bash-guard hooks)
├── codex/                   ← .codex/config.toml + agents/ (researcher/coder/auditor/mapper)
└── skills/                  ← 10 ab-* skills (triage, workflow, research, pm, architect,
                              test-writer, security, qa, review, debug)
                              Installed to BOTH .claude/skills/ and .agents/skills/.
```

## What ships verbatim vs what's a placeholder

See decisions.md row #4. Generic files (workflow, ONBOARDING, sync script, repo scaffold) ship verbatim. Project-specific files (STATUS, architecture, decisions, repos, conventions) ship as placeholders and are filled by the LLM at activation.

## Substitution contract

`agentboard init` substitutes EXACTLY 3 placeholders in the listed files:
- `{{PROJECT_NAME}}`
- `{{DESCRIPTION}}`
- `{{TODAY}}`

Any other placeholder is left for the LLM to fill at activation. Never add new substitution keys to init — the tool stays stack-agnostic.

## Root-entry marker contract

Agentboard-generated sections in CLAUDE.md/AGENTS.md/GEMINI.md are wrapped in:
```
<!-- agentboard:root-entry:begin v=1 -->
… agentboard content …
<!-- agentboard:root-entry:end v=1 -->
```
Re-activation replaces content between markers in place — never prepends a second copy. User's original content below is preserved.

## Decisions locked

- No stack-specific templates (no React, Django, Unity). The LLM writes conventions/{stack}.md per-project.
- Skills are dual-installed (.claude/skills + .agents/skills) because Claude Code and Codex/Gemini read different paths. Both get the same content.
- `.claude/settings.json` in templates/root/ ships with ALL hooks wired. Fresh init → hooks work on day 1 without running `install-hooks`.
- Template files that accept substitutions must use `{{UPPERCASE_SNAKE}}` — never `{{lowercase}}` or `${VAR}`.
