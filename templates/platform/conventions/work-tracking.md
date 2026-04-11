# Work Tracking Convention

## Purpose

Lightweight "current work" signal that survives context clears and parallel AI sessions.
Lives in `.platform/work/`. Complements `.platform/STATUS.md` (project-level feature status)
— `work/` is what you're touching *this session*, not what's shipped or planned long-term.

## Directory layout

```
.platform/work/
├── ACTIVE.md           ← registry; read every session start
├── <slug>.md           ← one file per active workstream
└── archive/
    └── <slug>.md       ← completed workstreams (grep-able history)
```

## Session start protocol (mandatory)

Read in order — stop as soon as you have enough to orient:

1. **`work/BRIEF.md`** — narrative brief: what we're building, why, current state, and which reference docs to load (§ "Relevant context")
2. **`work/ACTIVE.md`** — stream registry:
   - **0 streams** → proceed normally, ask user what to work on
   - **1 stream** → confirm: "Resuming **<stream>** — next: <next action>. Continue?"
   - **2+ streams** → ask user which one
3. Load `work/<slug>.md` only when you need full detail

## Scoped context loading (mandatory)

**Only load the reference files listed in `work/BRIEF.md` § "Relevant context".** Do not load the full `.platform/` pack.

- If the feature touches the backend → load `backend.md`. Not the frontend docs.
- If the feature touches one widget → load that widget's doc. Not the other widgets'.
- If the feature is UI-only → load the UI doc. Not the backend doc.
- **Never read `work/archive/*`** — completed work is irrelevant to the current feature.

This keeps context windows lean and prevents agents from being briefed on work that has nothing to do with their task. One feature = one reading list.

## Starting a new workstream

1. Copy `TEMPLATE.md` to `work/<stream-slug>.md`
2. Fill in: type, scope (3–5 bullets), done criteria (measurable), next action
3. Add a row to `ACTIVE.md`

Stream slug: short-kebab-case, e.g. `stripe-webhook-retry` or `menu-banner-bug`.

## During work

- Append to **Progress log** after each significant step (commit, test run, decision)
- Keep **Next action** current — this is what the next session resumes from
- Append to **Key decisions** when you make an architectural or product choice
- Update **Status** when it changes

## Concurrent AI sessions (Claude Code + Codex + Gemini)

No hard locks. The `Agent` column in `ACTIVE.md` is a soft signal:
- Set it to `claude-code`, `codex`, or `gemini` when you pick up a stream
- If you see a different agent owns a stream, check with the user before touching it
- Multiple agents CAN work different streams simultaneously — each has its own file

## Done ritual (agent-proposed, user-confirmed)

When all done criteria are met:
1. Agent sets status → `awaiting-verification`
2. Agent posts done-criteria checklist with ✅/❌ for each item
3. **User confirms** — agent cannot self-approve
4. On confirmation:
   - Move `work/<slug>.md` → `work/archive/<slug>.md`
   - Remove row from `ACTIVE.md`
   - Append one line to `.platform/log.md`
   - Update `memory/` if anything learned should persist cross-session

## What NOT to put in a stream file

- Full implementation plans (those live in chat)
- Large code snippets (those live in the codebase)
- More than ~60 lines total — if it's growing, you're over-documenting
