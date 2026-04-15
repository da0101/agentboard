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
