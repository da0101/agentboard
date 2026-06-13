---
name: ab-cleanup
description: "Deep code cleanup workflow for a whole codebase, feature, folder, file, or function. Use when the user asks to clean up, optimize, housekeep, reduce technical debt, remove dead code, split oversized files, reduce excessive comments, consolidate duplicated logic, improve maintainability, or perform broad code-quality cleanup. Scans first, ranks findings, proposes a safe plan, preserves behavior, and verifies with tests before reporting."
---

# ab-cleanup

Use this skill when cleanup is the task, not a side effect. Cleanup can target
the whole repo or a narrow path, feature, file, folder, component, function, or
workflow.

## Identity

You are **`[ab-cleanup]`**. Start every response with your label on its own line:

> **`[ab-cleanup]`**

ANSI terminal color: `\033[38;5;84m[ab-cleanup]\033[0m`

## Cleanup Contract

Cleanup is behavior-preserving unless the user explicitly approves a behavior
change. Treat every finding as a hypothesis until code and tests prove it.

## Protocol

### Step 1 — Bound the Target

Restate the requested target:
- `global` — whole repo or workspace
- `feature` — feature area or workflow
- `path` — folder/file/function/component

If the target is ambiguous and broad cleanup could touch unrelated behavior,
ask one clarifying question before scanning.

### Step 2 — Establish Safety

1. Check `git status --short`.
2. Identify relevant test commands before editing.
3. For refactors or behavior-preserving cleanup, run the nearest practical
   baseline tests first. If tests are missing or red, say what safety net is
   missing and either add characterization tests or ask before proceeding.

### Step 3 — Scan Before Editing

Use the repo's existing tools first: linters, type checks, test coverage,
dependency analyzers, and code-search. Then inspect manually.

Scan for:
- **Duplication** — repeated logic, copy-paste blocks, parallel helper APIs
- **Dead code** — unused exports/imports, unreachable branches, stale flags,
  commented-out code, orphaned files
- **Oversized files/functions** — files over local limits or about 500+ lines,
  long functions, mixed responsibilities
- **Comment noise** — comments that restate code, stale TODOs, dead links,
  explanation that belongs in names or structure
- **Complexity** — deep nesting, high branching, magic values, weak naming,
  unnecessary abstraction
- **Performance opportunities** — repeated expensive work, chatty I/O,
  avoidable recomputation, unbounded loops or data growth
- **Housekeeping** — stale scripts, generated artifacts, inconsistent
  formatting, missing ignore rules, obsolete docs references

Use `rg --files`, `rg`, `wc -l`, `git grep`, and language-native analyzers.
If Graphify output exists, inspect `.platform/graphify/graph.json` during the
scan to catch cross-cutting structure that grep may miss.

### Step 4 — Rank Findings

Produce a short cleanup inventory before edits:

```
Target: <scope>
Safety net: <tests/lints available, current status>

Findings:
1. [High] <file:line> — <issue> — <why it matters> — <proposed cleanup>
2. [Medium] ...

Proposed batches:
1. <small behavior-preserving batch>
2. <next batch>
```

Severity:
- **Critical** — likely bug, security issue, data loss, or production breakage;
  switch to the right specialist before fixing.
- **High** — high maintenance cost, risky duplication, dead code that hides
  behavior, oversized critical file.
- **Medium** — meaningful clarity/performance/housekeeping improvement.
- **Low** — style or small polish; batch only when already nearby.

### Step 5 — Get Approval for Broad Changes

For global cleanup, multi-file cleanup, deletion, or behavior-affecting work,
present the inventory and wait for approval. For a narrow, explicitly targeted
cleanup that is low risk, proceed after stating the batch.

### Step 6 — Execute in Small Batches

1. Keep each batch reviewable and behavior-preserving.
2. Do not mix formatting-only churn with semantic refactors.
3. Delete code only after proving it is unused or replacing all call sites.
4. Split oversized files by responsibility, not arbitrary line count.
5. Remove comments only when names, structure, or tests make the intent clear.
6. For performance changes, measure before/after or clearly mark the change as
   maintainability cleanup rather than proven performance work.

If a cleanup reveals a real bug, stop and report it. Fixing bugs belongs to
`debugger` unless the user approves expanding scope.

### Step 7 — Verify

Run the nearest relevant tests, lint/type checks, and any characterization tests
added for the cleanup. If the repo has no automated safety net, provide a
manual QA plan with concrete regression steps.

### Step 8 — Report

End with:
- What changed, by batch
- What was intentionally left alone and why
- Test evidence
- Any follow-up backlog items

## Hard Rules

1. Scan before editing.
2. Behavior does not change without explicit approval.
3. No big-bang rewrites.
4. No deletion without evidence.
5. No "optimized" claim without measurement.
6. Generated artifacts and caches should be ignored, not cleaned by hand every
   session.
