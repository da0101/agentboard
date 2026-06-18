# Contributing Skills to agentboard

## What is a community skill?

A `SKILL.md` file following the built-in skill format, with `origin: community`
in frontmatter. Community skills extend agentboard for domain-specific workflows
without modifying the core kit.

## Required frontmatter

```yaml
---
name: my-skill            # kebab-case, unique across the registry
description: "One sentence: what, for whom, when."
version: 1.0.0
origin: community
author: github-handle
---
```

Optional: `tags`, `harnesses`, `min_agentboard_version`, `argument-hint`, `allowed-tools`.
Full schema: `templates/platform/schemas/skill.schema.json`.

## Installing a community skill

```sh
ab skill add <url-to-raw-SKILL.md>
```

The CLI copies the file into `.claude/skills/<name>/SKILL.md` in the current project.

## Submitting for inclusion in the built-in pack

1. Fork this repo and create `community-skills/<skill-name>/SKILL.md`.
2. Open a PR against `develop`. Title: `skill: add <name>`.

Widely-used community skills are promoted into `templates/skills/` and ship with every `agentboard init`.

## Quality bar — required body sections

Your `SKILL.md` body must include: **Identity** (label + announcement format),
**Purpose** (problem + trigger), **Protocol** (numbered steps), **Hard rules**
(explicit prohibitions), and **Anti-patterns** (common failure modes).

## What we will not accept

- Stack-specific skills that only make sense for one project (use your own `.platform/` activation)
- Skills that duplicate a built-in (`ab-research`, `ab-debug`, etc.)
- Skills missing Hard rules or Anti-patterns sections
- Skills with `origin: agentboard` (reserved for the core pack)

## Minimal SKILL.md skeleton

```markdown
---
name: my-skill
description: "One-sentence summary of purpose and trigger."
version: 1.0.0
origin: community
author: your-github-handle
---

# my-skill — Short title

## Identity
You are **`[my-skill]`**. Start every response with your label on its own line.

## Purpose
What this skill does and when to invoke it.

## Protocol
1. Step one.
2. Step two.

## Hard rules
- Never do X.

## Anti-patterns
- Do not skip the Identity header.
```
