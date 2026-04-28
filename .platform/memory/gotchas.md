# Gotchas

_Landmines found in this codebase. Each line = one thing a fresh agent should know before touching the related area. Appended automatically during `agentboard close <slug>` harvest._

**Severity tiers** (use the emoji prefix):
- 🔴 **never-forget** — breaks prod, loses data, or wastes hours. Always surfaced in `agentboard brief`.
- 🟡 **usually-matters** — trips up most new work in the area. Surfaced when relevant domains are active.
- 🟢 **minor** — worth mentioning, not worth interrupting flow.

Format: `🔴 [domain or file] — one-line gotcha (incident date if applicable)`

---

## Entries

<!-- agentboard:gotchas:begin -->
🔴 [bash] — `local -a foo` leaves `foo` unbound under `set -u`. Always write `local -a foo=()`. Burned us in watch.sh and brief.sh — CI with bash 5 catches what bash 3.2 silently allows.
🔴 [tests] — `printf 'content...'` with a leading `-` is interpreted as a flag. Use `printf '%s\n' 'content'` for arbitrary strings. Hit this in migrate_layout_test.sh.
🔴 [bash] — `cmd | head -N` under `set -o pipefail` returns 141 (SIGPIPE) when cmd can't flush. Use `awk 'NR<=N'` or a for-loop with break. Seen in watch.sh, tests.
🟡 [tests] — Integration test fixtures need `git add -A && git commit` to reach a fully-clean `git status`. Partial `git add .platform .claude CLAUDE.md` leaves untracked files that break watch tests expecting empty porcelain.
🟡 [migrate-layout] — `agentboard update` can create empty `memory/*.md` placeholders that conflict with real root-level files during migration. Fix: update detects legacy root files and skips the placeholder; migrate-layout detects byte-identical placeholders and overwrites them. Shipped v1.5.x.
🟡 [install-hooks] — existing `.claude/settings.json` without the bash-guard marker refuses merge without `--force`. Deliberate — don't silently clobber user customizations. `--force` backs up to `.agentboard-backup-<ts>`.
🟡 [post-commit/log.md] — `>>` appends to the bottom of log.md but the header says "newest at top". Always use awk prepend-after-separator: `awk '/^---$/ && !done { print; print entry; done=1; next } { print }'`. Fixed in post-commit hook v1.5.7.
🟡 [watch/scheduler] — renaming the project directory after `agentboard watch --install` breaks uninstall; the scheduler label/unit name is baked from the slug at install time. Run `--uninstall` before renaming, or remove the plist/units manually.
🟡 [watch/scheduler] — launchd inside AI agent sandboxes (Claude Code, etc.) returns "Operation not permitted" when executing repo binaries. Always test `watch --install` / `--status` / `--uninstall` in a real terminal, not inside the agent workspace.
🟢 [sed] — BSD sed (macOS) and GNU sed differ on alternation. Don't use `-E 's|(a|b)|x|g'` cross-platform. Loop per-name instead.
🟡 [event-logger] — `event-logger.sh` has its own inline copy of stream-resolution logic (`_resolve_stream`, `_session_stream_lookup`, `_remember_session_stream`) that duplicates `project_state.sh` helpers. Works, but can drift. If stream resolution bugs appear, check both copies.
🟡 [templates] — Edits to `templates/platform/scripts/*` don't apply to an existing project until `agentboard update` is run. The deployed `.platform/scripts/` is a snapshot; always run update after changing templates.
🟡 [runtime artifacts] — `.platform/` contains transient files like `events.jsonl`, `.daemon-port`, and `.file-locks.json`; in normal user repos they are commit-prone unless `init`/`update` also installs ignore coverage. Treat them as runtime state, not project state.
🔴 [lock] — `_lock_session_id` must never use `$PPID` as the fallback. Each `run_cli_capture` call forks a new subshell with a different PPID, so acquire and release use different keys and the lock is never released. Fallback must be a stable constant (`${provider}-anonymous`) matching the daemon's own `normalizeSessionId`. Fixed v1.8.0.
🟡 [close/domain-gap] — `_close_print_domain_gap` compares all files touched in `base_branch..HEAD` against domain doc text. When a stream touches many commits (or base_branch is far behind), the gap list is overwhelmingly noisy with unrelated files. It is informational only — do not treat it as a blocklist.
<!-- agentboard:gotchas:end -->
