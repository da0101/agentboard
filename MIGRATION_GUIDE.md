# Agentboard Migration Guide

Use this when a project already has an older Agentboard `.platform/` layout and you want to upgrade it to the current metadata-driven format.

This guide is for:

- old projects with legacy `work/*.md` stream files
- old projects with legacy `domains/*.md` files
- old projects with a legacy multi-stream `work/BRIEF.md`

This guide is not for:

- fresh installs
- projects that already pass `agentboard doctor` with no migration warnings

---

## What gets upgraded

Current Agentboard expects:

- stream metadata frontmatter in `.platform/work/*.md`
- domain metadata frontmatter in `.platform/domains/*.md`
- repo-aware sync state in `.platform/scripts/sync-context.sh`
- a modern single-stream `work/BRIEF.md`

The migration workflow upgrades those pieces in stages so you can preview before writing.

---

## Recommended flow

If `agentboard` is not on your `PATH`, use the full binary path:

```bash
'/absolute/path/to/agentboard/bin/agentboard'
```

Example:

```bash
'/Users/danilulmashev/Documents/GitHub/agentboard/bin/agentboard'
```

Then run this sequence inside the target project:

```bash
agentboard update
agentboard migrate
agentboard migrate --apply
agentboard brief-upgrade <stream-slug>
agentboard brief-upgrade <stream-slug> --apply
agentboard doctor
```

If you are using the full binary path, substitute it in each command.

---

## Step by step

### 1. Update the installed kit

```bash
agentboard update
```

This refreshes shipped process files and preserves project-specific state.

For hub-style projects, `update` also preserves or rebuilds the repo sync list in `.platform/scripts/sync-context.sh`.

### 2. Preview metadata migration

```bash
agentboard migrate
```

This does not change files. It shows which legacy stream and domain files can be upgraded safely.

Review the inferred:

- `domain_slugs`
- `repo_ids`

If the preview obviously maps a stream to the wrong domain, stop and fix that before applying.

### 3. Apply metadata migration

```bash
agentboard migrate --apply
```

This upgrades legacy:

- `.platform/work/*.md` stream files
- `.platform/domains/*.md` domain files

It intentionally does not rewrite a legacy multi-stream `work/BRIEF.md`.

### 4. Choose the single-stream BRIEF focus

Old projects often have a legacy `work/BRIEF.md` that points to multiple active streams.

Current Agentboard wants one brief focused on one active stream at a time.

Preview a rewritten BRIEF for the stream you want:

```bash
agentboard brief-upgrade <stream-slug>
```

Examples:

```bash
agentboard brief-upgrade care-plan-pdf-flow
agentboard brief-upgrade medications-admin-api-errors
```

Choose the stream that should be the main session-entry brief right now.

### 5. Apply the BRIEF upgrade

```bash
agentboard brief-upgrade <stream-slug> --apply
```

This rewrites `work/BRIEF.md` into the modern single-stream format using:

- the chosen stream file
- that stream’s done criteria
- its key decisions
- its next action
- its domains and repo references

### 6. Verify the project

```bash
agentboard doctor
```

Target outcome:

```text
Doctor passed
  errors: 0   warnings: 0
```

---

## Fast path

If you already know the target BRIEF stream, the practical migration sequence is:

```bash
agentboard update
agentboard migrate
agentboard migrate --apply
agentboard brief-upgrade <stream-slug> --apply
agentboard doctor
```

---

## How to choose the BRIEF stream

Pick the stream that should answer this question:

> If a fresh Claude/Codex/Gemini session starts right now, what is the one stream it should orient around first?

Good choices:

- the stream currently in active implementation
- the stream most likely to receive the next engineering session
- the stream with the highest user or delivery urgency

Bad choices:

- an old reference-only analysis stream
- a stream that is effectively parked
- a stream you do not want new sessions to resume by default

Remember: `ACTIVE.md` can still list multiple streams. The BRIEF is just the default orientation layer.

---

## Typical outcomes

After a successful migration:

- stream files have `stream_id`, `slug`, `status`, `domain_slugs`, `repo_ids`, and timestamps
- domain files have `domain_id`, `slug`, `repo_ids`, and timestamps
- `doctor` can validate repo/domain/stream integrity
- `handoff` can produce low-token resume packets
- old projects become compatible with the current workflow and validation model

---

## Troubleshooting

### `agentboard: command not found`

Use the full binary path or install Agentboard onto your `PATH`.

### `migrate` preview shows wrong domains

Do not apply yet. Inspect the relevant legacy stream/domain files first.

### `doctor` still warns after `migrate --apply`

Most likely causes:

- legacy `work/BRIEF.md` still needs `brief-upgrade`
- repo registry in `.platform/repos.md` is incomplete
- the project has unusual custom files that need a manual pass

### Multiple active streams but no clear BRIEF choice

Keep `ACTIVE.md` as-is. Just choose the stream that should be the default orientation entry point for now.

---

## Recommended project-by-project checklist

For each old project:

1. Run `update`
2. Run `migrate`
3. Review the preview
4. Run `migrate --apply`
5. Preview `brief-upgrade` for the stream you want
6. Run `brief-upgrade <stream-slug> --apply`
7. Run `doctor`
8. Commit the project changes in that project repo

That is the safest repeatable migration loop.

---

## Upgrading to the lean layout (any existing project)

Projects set up before the kernel / protocols / knowledge-card changes carry pollution and a heavy always-loaded context. This is the whole upgrade; every step is previewable and nothing is deleted without a copy.

```bash
ab update            # refresh verbatim files: protocols/, kernel, roles, routing.tsv, models.tsv
ab tidy              # REPORT: archived streams, graphs, session dumps, orphaned QA, extra skills,
                     #         session-start tokens, stale streams, drifted cards
ab tidy --apply      # do the safe subset (copies to ~/.agentboard/cold/<project>/ first)
ab entry adopt       # PREVIEW slimming an old CLAUDE.md / AGENTS.md / GEMINI.md that has no markers
ab entry adopt --apply   # writes it; the original is saved to the cold store
ab doctor            # session start should now be under 2,000 tokens
ab usage ingest --all && ab usage report    # (optional, needs sqlite3) real token numbers
```

What each step will and will not do:

- **`ab tidy --apply`** moves `work/archive/`, `graphify/`, `memory/session-*.md` and QA files of streams that no longer exist out of the repo (to the cold store), removes rotated event logs and closed rows in `ACTIVE.md`, prunes unmodified extra skills and syncs the kernel into marker-managed entry files. It never touches open streams, `domains/`, `memory/` or `knowledge/`. Removals appear in `git status` — review and commit when ready.
- **`ab entry adopt`** drops only *generic* protocol sections (Workflow, Session Start, New Task Bootstrap, Manual QA, Closure, Subagent Dispatch, Skills, Reference Pack, …). Anything it cannot classify is kept, project-specific headings like "Clinical workflow engine" are kept, and imperative rules found inside dropped sections that the kernel does not state (for example "never commit unless asked") are carried over into a "Carried-over rules" section for you to review. Text preserved under an "Existing … content" heading stays verbatim after the markers.
- **Closing streams changes.** `ab close` now merges the stream's `## Knowledge delta` into the domain cards and removes the stream file (a copy goes to the cold store) instead of archiving it in the repo. Write the delta as you work; see `ab protocol closure`.
- **Worktrees are on demand.** `ab worktree status` shows leftovers; `ab worktree clean --apply` (or `ab tidy --worktrees --apply`) removes merged, clean ones.
- **Skills.** The 12-skill core is installed by default; the rest are opt-in (`ab skill list`, `ab skill install <name>`). `ab skill prune` removes unmodified extras.

Rollback: everything moved is under `~/.agentboard/cold/<project>/`, and entry-file originals are saved there too (`adopt-<date>/`). For tracked files, `git checkout -- <path>` also restores.

### Hub that must not touch its sibling repos

`sync-context.sh` was designed to keep every repo's `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` identical, and `ab update` / `ab bootstrap` write the sibling repos from `repos.md` into its `REPOS` list. If the siblings belong to teams that do not use Agentboard, create `.platform/sync-scope` containing the single word `hub-only`; the list then holds the hub alone on every update, and `ab sync --apply` can never rewrite a sibling's entry files.
