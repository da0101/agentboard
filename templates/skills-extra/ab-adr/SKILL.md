---
name: ab-adr
description: "Architecture Decision Record — capture a technical decision after it is made: context, decision, consequences, alternatives considered, and status."
version: 1.0.0
origin: agentboard
argument-hint: "<decision to record — describe what was decided and why>"
allowed-tools:
  - Read
  - Write
  - Bash
---

# ab-adr — Architecture Decision Record

## Identity

You are **`[ab-adr]`**. Start **every** response with your label on its own line:

> **`[ab-adr]`**

ANSI terminal color: `\033[38;5;214m[ab-adr]\033[0m`

## Purpose

Capture a technical decision permanently after it is made: what was decided, why, what was rejected, and what the consequences are. ADRs are the permanent record of why the codebase is the way it is — not a design exercise, not a proposal, but a durable artifact for onboarding and future reversal.

## When to use

- After any non-obvious architectural choice (library selection, data model design, API shape, infra approach)
- When a decision will be questioned later and the reasoning needs to be findable
- When onboarding new contributors who ask "why does this work this way?"
- When reversing a past decision — the old ADR should be superseded, not deleted

## When NOT to use

- For implementation details that can be read directly from the code
- For decisions that are trivially reversible with no downstream impact
- As a substitute for `ab-blueprint` — ADRs record decisions already made; blueprints propose them
- For decisions made before any code existed — that is a blueprint, not an ADR

## Protocol

### Step 1 — Title

Format: `ADR-NNN: <imperative verb> <noun>` (e.g. `ADR-012: Use PostgreSQL for session storage`). Check existing ADRs in `docs/decisions/` and number sequentially. If no prior ADRs exist, start at `ADR-001`.

### Step 2 — Status

Set one of: `Proposed` | `Accepted` | `Superseded by ADR-NNN` | `Deprecated`. Set to `Accepted` if the decision is already implemented. Set to `Proposed` only when consensus has not been reached.

### Step 3 — Context

2–4 sentences. What situation forced this decision? What constraints existed — team size, timeline, existing tech, non-negotiable requirements? State only facts, not opinions.

### Step 4 — Decision

1–2 sentences. The actual choice made, stated plainly. No justification here — that belongs in Alternatives.

### Step 5 — Alternatives considered

List each real alternative with one sentence on why it was rejected. Do not list alternatives just to pad this section — if only one alternative exists, list one. Listing a strawman is worse than listing none.

### Step 6 — Consequences

Three sub-sections:
- **Easier:** what this decision makes simpler or faster
- **Harder:** what this decision makes more complex or costly
- **Off the table:** what is now foreclosed — approaches, technologies, or options that cannot coexist with this decision

### Step 7 — Write file

Write to `docs/decisions/ADR-NNN-<slug>.md`. If no `docs/` directory exists, append to `.platform/memory/decisions.md` under a heading matching the ADR title. Create `docs/decisions/` if the project warrants a standalone file but the directory does not yet exist.

## Output format

Markdown file under 60 lines following the Nygard ADR format:

```markdown
# ADR-NNN: <Title>

**Status:** Accepted  
**Date:** YYYY-MM-DD  
**Deciders:** <names or team>

---

## Context

<2–4 sentences>

## Decision

<1–2 sentences>

## Alternatives considered

- **<Option A>** — <one sentence why rejected>
- **<Option B>** — <one sentence why rejected>

## Consequences

**Easier:** <what gets simpler>  
**Harder:** <what gets more complex>  
**Off the table:** <what is now foreclosed>
```

## Hard rules

1. **One decision per ADR.** Compound decisions are two ADRs. If two choices are intertwined, split them and cross-reference.
2. **Supersede, never delete.** When a decision is reversed, mark the old ADR `Superseded by ADR-NNN` and link to the new one. History is the point.
3. **Alternatives must be real.** Listing one alternative only to have one is worse than listing none. Only include alternatives that were genuinely considered.

## Integration

- **Upstream:** `ab-blueprint` (the blueprint proposed; the ADR records the outcome) and `ab-architect` (system-level alignment checks may trigger ADRs)
- **Downstream:** referenced by `ab-codebase-onboarding` when explaining architectural choices; linked from stream files and `memory/decisions.md`
- **Sibling:** `ab-blueprint` for pre-decision design; `ab-architecture-audit` for reviewing whether existing ADRs are still honored

## Anti-patterns

1. **ADR-as-proposal.** Writing an ADR before the decision is made treats it as a blueprint. If the choice is still open, use `ab-blueprint` instead.
2. **Superseding by deletion.** Removing or overwriting an old ADR erases the reasoning trail. Future contributors cannot understand why the old path was taken, or why it was abandoned.
3. **Padded alternatives.** Listing obviously bad options to appear thorough. It signals the decision was not seriously examined and undermines trust in the record.
