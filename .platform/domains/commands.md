---
domain_id: dom-commands
slug: commands
status: active
repo_ids: [repo-primary]
related_domain_slugs: [core, templates]
created_at: 2026-04-17
updated_at: 2026-04-17
---

# commands

## What this domain does

Implements every user-invoked `agentboard <cmd>` verb. Each command is a standalone bash file in `lib/agentboard/commands/` sourced by the thin dispatcher in `bin/agentboard`.

## Commands shipped (v1.5.2)

| Command | File | Purpose |
|---|---|---|
| init | init.sh | Scaffold `.platform/` + root entry files + skills + `.codex/` |
| update | update.sh | Refresh shipped process files; add-if-missing memory/ placeholders |
| migrate | migration.sh | Upgrade legacy stream/domain files to v1 frontmatter |
| migrate-layout | migrate_layout.sh | v1.5 memory/ reorg; placeholder overwrite; stale-ref sweep |
| doctor | doctor.sh | Validate `.platform/` state + metadata + repo registry |
| bootstrap | bootstrap.sh | Discover repos + suggest starter domains/streams |
| new-domain | streams.sh | Create `.platform/domains/<slug>.md` |
| new-stream | streams.sh | Create `.platform/work/<slug>.md` + register in ACTIVE.md |
| resolve | streams.sh | Look up stream/domain/repo by canonical id |
| handoff | streams.sh | Print load order + Resume state + staleness warning |
| progress | progress.sh | Append `git diff --stat` to stream's ## Progress log |
| checkpoint | checkpoint.sh | Overwrite ## Resume state; auto-log usage on cumulative flags |
| close | close.sh | Harvest checklist → archive stream + run `usage learn --apply` |
| brief | brief.sh | Session-start compact view: streams, gotchas, questions, usage |
| watch | watch.sh | Background multi-stream poller (git status) → auto-checkpoint |
| install-hooks | install_hooks.sh | Wire Claude Code PreToolUse guards |
| usage | usage.sh | SQLite token tracking + summary/dashboard/learn |
| sync | session.sh | Run `.platform/scripts/sync-context.sh` |
| status | session.sh | Print STATUS.md |
| add-repo | system_setup.sh | Scaffold entry files into a sibling repo |

## Dispatcher contract

- `bin/agentboard` sources every `lib/agentboard/commands/*.sh` at load time
- Main dispatcher maps `case "$cmd" in init) cmd_init "$@" ;; …` — one-line entries
- Every command must define a `cmd_<verb>` function, accept `--help` / `-h`, and return non-zero on error
- Commands should use helpers from `lib/agentboard/core/*.sh` — never duplicate frontmatter parsing or color output

## Decisions locked

- One command = one file in `commands/`. Don't co-locate multiple verbs unless they share ≥50% of their logic (streams.sh is the tolerated exception: new-domain/new-stream/resolve/handoff all share frontmatter + ACTIVE.md logic).
- No command may require a runtime outside bash + standard unix tools (`awk`, `sed`, `grep`, `git`). `sqlite3` is opt-in for usage.sh only.
- All user-facing paths are relative (`./.platform/...`) not absolute — command runs from project root.
- Help text is required (`-h|--help` branch in every parser) — see help.sh for the catalog shown by `agentboard help`.

## Key files

- `bin/agentboard` — dispatcher
- `lib/agentboard/commands/*.sh` — 20 command files
- `lib/agentboard/commands/help.sh` — catalog shown by `agentboard help`
