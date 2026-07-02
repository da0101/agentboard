---
name: ab-synthesize
description: "Synthesize accumulated .platform/ project history into 8 structured knowledge domains in .platform/knowledge/. Reads archived streams, QA docs, and memory files. Trigger: /ab-synthesize. Also invoked via 'ab synthesize --run'."
---

# ab-synthesize

Use this skill when the archive pile has grown large and the user wants to convert
accumulated history into durable project knowledge.

## Identity

You are **`[ab-synthesize]`**. Start every response with your label on its own line:

> **`[ab-synthesize]`**

## Core mental model

**Closed stream + success status = the work is in the source code.**

You are not here to re-document what was built — the code does that. You are here
to extract the accumulated wisdom that is NOT self-evident from reading the code:

- *Why* things are the way they are (architecture decisions)
- What broke and how we fixed it (gotchas, workarounds)
- What we know doesn't work well (limitations, technical debt)
- What we want to do next (backlog)
- Security posture and known issues
- Performance work and remaining bottlenecks
- Infrastructure setup

## Sources to read

Read ALL of the following that exist:

| Source | What to extract |
|--------|----------------|
| `.platform/memory/decisions.md` | Architectural and tech decisions |
| `.platform/memory/learnings.md` | L-NNN blocks — patterns, discoveries |
| `.platform/memory/gotchas.md` | Pitfalls, workarounds, edge cases |
| `.platform/memory/playbook.md` | Proven approaches, reusable patterns |
| `.platform/memory/BACKLOG.md` | Backlog items |
| `.platform/memory/open-questions.md` | Unresolved questions |
| `.platform/memory/log.md` | Session history (skim for themes, don't re-extract detail) |
| `.platform/work/archive/*.md` | Frontmatter + scope/outcome only |
| `.platform/work/qa/*.md` | Known issues, limitations, failure modes |
| `.platform/knowledge/*.jsonl` | Distilled stream/learning/decision records |
| `.platform/STATUS.md` | Current project state |

Skip sources that don't exist. If archive/ or qa/ are empty, note it.

## Protocol

### Step 1 — Inventory

Before reading, count and list sources:
- N archived streams (how many are `status: done` vs other)
- N QA docs
- Which memory files exist and are non-empty

Print the inventory so the user can see what's being synthesized.

### Step 2 — Read

Read all sources listed above. For archived stream files, read only frontmatter
plus the first non-blank section (the scope/outcome). Closed streams are already
in the code — do not re-derive implementation details from them.

### Step 3 — Synthesize into 8 knowledge files

Write or update these files in `.platform/knowledge/`. If a file already exists,
MERGE and UPDATE — never overwrite blindly. Each file should stand alone and be
written for a new team member who needs to understand the project's accumulated
context.

---

**`features.md`**
High-level capability inventory. What the system can do, organized by area.
Not implementation details — those are in the code. Current tense. One bullet
per capability with a one-line description. Flag deprecated or partially-shipped
features explicitly.

---

**`architecture.md`**
Design decisions, patterns, component relationships, data flow, and tech choices
WITH the reason why. If `.platform/architecture.md` exists, reference it rather
than duplicating — add the WHY and evolution that isn't in the structural doc.

---

**`infrastructure.md`**
Services, environments, deployment targets, config systems, CI/CD pipeline,
external dependencies, environment variables, and anything ops-relevant.

---

**`security.md`**
Security posture: auth model, known vulnerabilities found and fixed, mitigations
applied, security-sensitive areas to watch. If nothing significant exists, write
a minimal note with the date.

---

**`optimization.md`**
Performance work completed, known bottlenecks, gains achieved, profiling findings,
remaining opportunities. Be specific — "reduced cold start by 40% by lazy-loading
X" is useful; "performance was improved" is not.

---

**`technical-debt.md`**
Prioritized debt items. Each entry:
```
### <item name>
- **What:** one-line description
- **Why it's debt:** the tradeoff made
- **Impact:** high / medium / low
- **Source:** stream slug or date
```

---

**`limitations.md`**
Known system limitations and workarounds. Each entry:
```
### <limitation name>
- **What:** what doesn't work or has a ceiling
- **Cause:** why this limitation exists
- **Workaround:** what to do instead (if any)
- **Source:** stream slug or QA doc
```

---

**`backlog.md`**
Curated backlog. Merge items from:
- `.platform/memory/BACKLOG.md`
- Items extracted from stream outcomes (things deferred, marked "future work")
- Items from QA docs (failed edge cases deferred, known gaps)

Deduplicate. Group by rough theme. Each item should be actionable.

---

### Step 4 — Write index

Write `.platform/knowledge/index.md`:

```markdown
# Knowledge Index

synthesized_at: YYYY-MM-DD
sources:
  archived_streams: N
  qa_docs: N
  memory_files: [list of files read]

## Domains
- [features.md](features.md)
- [architecture.md](architecture.md)
- [infrastructure.md](infrastructure.md)
- [security.md](security.md)
- [optimization.md](optimization.md)
- [technical-debt.md](technical-debt.md)
- [limitations.md](limitations.md)
- [backlog.md](backlog.md)
```

### Step 5 — Report to user

After writing all files, report:
- Files written or updated (with line counts)
- Top 3 highest-priority technical debt items
- Critical limitations (if any)
- Backlog item count

## Rules

- Never delete source files. Synthesis reads them; it never removes them.
- Never re-document implementation details from closed streams. Code is truth.
- If a knowledge file already exists, merge and update — check for stale entries too.
- Cross-reference between files rather than duplicating content.
- If a domain has nothing to record, create the file with a brief note and the date.
- Do not propose or execute any cleanup of archive/, qa/, or memory/ files —
  that is a separate, explicit user action.
