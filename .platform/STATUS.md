# Agentboard — Current Status

Last updated: 2026-06-20

> Bash CLI for shared work-state across Claude Code, Codex CLI, and Gemini CLI, plus a VS Code extension with a real-time live dashboard. Dogfooding itself since v1.5.2.

---

## Feature areas

| Area | Status | Last touched | Notes |
|---|---|---|---|
| Core CLI (init/doctor/status) | ✓ Done | 2026-04-17 | Stable. Pure bash, zero runtime deps. |
| Stream management (new-stream/handoff/checkpoint/close) | ✓ Done | 2026-04-17 | Ships in v1.5.x. Checkpoint auto-logs usage when cumulative flags given. |
| Memory compounding (brief/close harvest) | ✓ Done | 2026-04-17 | gotchas/playbook/open-questions populated by `close` ritual. |
| Daemon orchestration + file locks | ✓ Done | 2026-04-18 | Optional local Node daemon, session-scoped lock ownership, Claude hook enforcement, Codex/Gemini lock guidance. |
| Watch daemon | ✓ Done | 2026-04-17 | Multi-stream support added in v1.5.1. |
| Usage tracking + learn | 🔵 Exists | 2026-04-17 | SQLite-backed. Cumulative mode added. Learn detects Opus-on-trivial patterns. |
| Commit guard (Claude Code hook) | ✓ Done | 2026-04-17 | PR #19 merged. PreToolUse ask on destructive git / rm -rf. |
| VS Code extension — Live dashboard | ✓ Done | 2026-06-20 | v2.1.0 shipped. Session columns, WORKFLOW (collapsible, per-agent blue/green), SUB-AGENTS (staleness-aware), ACTIVITY (collapsible, inner scroll, git diff stats +N/-N). |
| VS Code extension — Catalog tab | ✓ Done | 2026-06-20 | v2.1.0. Expandable descriptions, "used by" session badges. |
| VS Code extension — Security fixes | ✓ Done | 2026-06-20 | v2.1.0: esc() quotes all interpolated values, relTime NaN guard, fmtModel crash guard, openStream path validation, CSP img-src locked. |
| VS Code extension — Codex dashboard | ⧗ Pending | 2026-06-20 | Stream file created. Planned for v2.1.1. |
| Watch auto-install (launchd/systemd) | ⧗ Pending | — | v1.6 Phase 2. Next up. |
| Post-commit Progress log hook | ⧗ Pending | — | v1.6 Phase 3. |
| Stream templates by --type | ⧗ Pending | — | v1.7 Phase 4. |
| agentboard onboard | ⧗ Pending | — | v1.7 Phase 5. 2-min fresh-machine setup. |

**Legend:**
- ✓ Done — shipped, tested, merged
- 🔵 Exists — in place but may need review
- ⧗ Pending — planned, not started
- ⚠ Flagged — known issue that needs attention
- 🔴 Deferred — decided to punt (reference `memory/decisions.md` entry)

## Immediate priorities

1. **VS Code v2.1.1: Codex dashboard support** — stream file created; implement Codex-specific live.json writer and dashboard panel variant
2. **v1.6 Phase 2: watch --install** — removes "I forgot to start watch" failure mode
3. **v1.6 Phase 3: post-commit hook** — free Progress log population on every commit
4. **v1.6 dogfood week on takecare-platform** — measure if the enforcement actually reduces drift

## Open decisions

| # | Question | Deadline |
|---|---|---|
| 1 | Cross-CLI commit guard for Codex/Gemini (shell shim vs accept honor-system)? | After v1.6 ships |
| 2 | Single-command `agentboard onboard` scope — interactive or `--yes` first? | v1.7 kickoff |
| 3 | Codex dashboard: poll live.json via file watcher or embed a small HTTP bridge? | v2.1.1 kickoff |

## Release blocklist

Things that must be resolved before v1.6.0 CLI ships:

- [ ] Phase 2 merged + CI green
- [ ] Phase 3 merged + CI green
- [ ] One full day of Claude↔Codex dogfooding on takecare-platform with no manual watch-start / checkpoint / handoff

Things that must be resolved before VS Code v2.1.1 ships:

- [ ] Codex dashboard stream implemented and verified
- [ ] Extension marketplace publish tested end-to-end

## Known gotchas (pinned)

- **Bash 3.2 strict mode empty arrays** — `local -a x` leaves x unbound under `set -u`. Always `local -a x=()`. We've been burned twice (watch.sh, brief.sh).
- **BSD sed vs GNU sed alternation** — `-E` required + no `|` alternation in basic mode. Use per-name loops.
- **SIGPIPE with `head`** — `cmd | head -N` under `set -o pipefail` returns 141 when `cmd` can't flush. Use `awk 'NR<=N'` or `for f in glob; do ... break; done`.
- **`printf 'format...'` with leading `-`** — printf treats `-` as flag. Use `printf '%s\n' 'content'` for arbitrary strings.
- **VS Code dashboard XSS surface** — all dynamic values injected into the webview HTML must pass through `esc()` (HTML-entity escaping); any new data field added to dashboard.js needs an `esc()` wrap. Reviewed in v2.1.0 security pass.
- **live.json path** — extension reads from `~/.agentboard/live.json` (global), not workspace-local. Bridging across VS Code windows by design (decision #28 candidate).

## File size violations (300-line rule)

- `usage.sh` — ~500 LOC (SQLite + dashboard + learn logic). Split candidate for v1.6.
- `base.sh` — ~510 LOC (color/fs/frontmatter helpers). Less urgent; tightly coupled.
- `project_state.sh` — ~470 LOC. Less urgent.

---
