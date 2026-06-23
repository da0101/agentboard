---
stream_id: stream-agentboard-os
slug: agentboard-os
type: feature
status: awaiting-verification
agent_owner: claude
domain_slugs: [agent-os]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/agentboard-os
created_at: 2026-06-16
updated_at: 2026-06-17
closure_approved: false
---

# agentboard-os

## Scope

Bring agentboard from a context scaffolding kit to a full agent OS, closing the gap with ECC (affaan-m/ecc) across two phases.

**Phase 1 — The OS Kernel** (current focus):
1. **SOUL.md + RULES.md templates** — identity + behavioral rules shipped in every `agentboard init`
2. **HUD contract** — `agentboard.hud-status.v1` JSON schema (context, tools, agents, todos, checks, cost, risk, queue)
3. **Memory persistence hook** — post-session hook that auto-writes learned facts to `.platform/memory/`
4. **Harness expansion** — Cursor (`.cursor/`), Zed (`.zed/`), Kiro (`.kiro/`), OpenCode (`.opencode/`) adapter dirs in init + update + sync
5. **Cross-harness skill sync** — `ab sync-skills` command (distinct from existing `ab sync` context sync) that pushes skills/roles to all detected harness dirs
6. **npm distribution** — `agentboard` npm wrapper, `npx agentboard init` install path
7. **Manifests + schemas** — YAML frontmatter standard for skills/roles, JSON schema validation on init/update
8. **New skills (7)** — `ab-verification-loop`, `ab-agent-eval`, `ab-skill-scout`, `ab-codebase-onboarding`, `ab-tdd`, `ab-canary`, `ab-token-budget`

**Phase 2 — The OS Surface** (pending Phase 1):
9. **VS Code extension** — sidebar reading HUD contract: stream status, active agents, cost, risk flags
10. **Security tooling** — `ab-agentshield` hook + expanded `ab-security` skill with bounty-hunter mode
11. **Platform value loop** — usage pattern capture → skill improvement suggestions surfaced in `agentboard brief`
12. **More skills (5)** — `ab-benchmark`, `ab-browser-qa`, `ab-architecture-audit`, `ab-search-first`, `ab-strategic-compact`
13. **Enhanced dashboard** — richer `agentboard dashboard` with per-stream cost, skill usage, model breakdown

Out of scope: ECC's 271 domain-specific skills (android-clean-arch, cisco-ios, etc.), the Hermes operator story, i18n of docs, commercial GitHub App.

## Done criteria

### Phase 1
- [ ] Research-backed plan approved by user (done — approved 2026-06-16).
- [ ] Isolated worktree exists for `feature/agentboard-os` (done — `/Users/danilulmashev/Documents/GitHub/agentboard-agentboard-os`).
- [x] SOUL.md + RULES.md added to `templates/platform/` and documented in ACTIVATE.md.
- [x] HUD contract JSON schema at `templates/platform/schemas/agentboard.hud-status.v1.json`.
- [x] Memory persistence hook implemented and wired into `ab install-hooks` / `ab init`.
- [x] Cursor, Zed, Kiro, OpenCode adapter dirs added to `templates/` and `ab init`/`ab update`.
- [x] `ab sync-skills` command implemented, registered in `bin/agentboard`.
- [x] npm wrapper (`package.json` + thin bin shim) at repo root.
- [x] Manifest YAML schema + validation hooked into init/update.
- [x] All 7 new skills present in `templates/skills/` and runtime provider dirs.
- [x] Tests cover each new concern; `bash tests/unit/agentboard_os_phase1_test.sh` passes (exit 0).
- [x] File size ratchet passes (exit 0).
- [ ] Manual verification: fresh `agentboard init` creates all new dirs/files correctly. ← needs user sign-off

### Phase 2
- [x] VS Code extension scaffolded — `extensions/vscode/` with HudProvider + StreamsProvider.
- [x] `agentshield.sh` PreToolUse hook + `ab-security` expanded with bounty-hunter mode.
- [x] Value loop: `brief_patterns.sh` surfaces skill usage, costliest stream, debug signals in `ab brief`.
- [x] 5 additional skills: ab-benchmark, ab-browser-qa, ab-architecture-audit, ab-search-first, ab-strategic-compact.
- [x] Enhanced dashboard: skill frequency, per-stream cost, model breakdown sections.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-16 — Base on `develop` not `main` — develop is the PR target branch; main is ahead by 5 commits (qa-journal, manual-qa-gate, version bump) that will flow back via develop→main after this stream lands.
2026-06-16 — `ab sync-skills` as a new command, not replacing `ab sync` — existing `ab sync` is context sync (CLAUDE.md etc.); harness skill distribution is a different concern and shouldn't break existing users.
2026-06-16 — HUD contract is a JSON schema first, VS Code extension second — defines the data format once, any renderer (terminal, web, IDE) can consume it without coupling.
2026-06-16 — npm wrapper is a thin shim (bash passthrough), no logic in JS — keeps the zero-required-deps invariant intact; npm is a distribution mechanism only.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/Users/danilulmashev/Documents/GitHub/agentboard-agentboard-os` | `feature/agentboard-os` | `develop` | no install needed; bash CLI + shell tests | `bash tests/unit.sh` / focused `bash tests/unit/*_test.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-17 by danilulmashev (auto)
- **What just happened:** (auto) 8b303a3: docs: update README and extension README for VS Code extension + control plane
- **Current focus:** —
- **Next action:** (auto-saved from commit — update next action manually)
- **Blockers:** none

## Progress log

2026-06-17 20:39 — (auto) 8b303a3: docs: update README and extension README for VS Code extension + control plane

2026-06-17 00:00 — Phase 2 complete: 26 files, 14 agents, all tests green. VS Code ext, agentshield, value loop, 5 skills, enhanced dashboard.
2026-06-17 00:00 — Phase 1 complete: 40 files, 17 agents, all tests green. SOUL.md, RULES.md, HUD schema, memory hook, 4 harness dirs, npm wrapper, ab sync-skills, ab validate, 7 new skills.
2026-06-16 00:00 — Registered agentboard-os stream; worktree created at `/Users/danilulmashev/Documents/GitHub/agentboard-agentboard-os`; multi-agent workflow dispatched for Phase 1 implementation.

## Open questions
