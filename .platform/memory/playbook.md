# Playbook

_How work actually gets done in this project. Shortcuts, commands, dev rituals that a 20-year employee would know. Appended during `agentboard close <slug>` harvest._

Format: `- **[area]** — one-line practice (why/when)`

---

## Entries

<!-- agentboard:playbook:begin -->
- **[tests]** — always run `bash tests/unit.sh` AND `bash tests/integration.sh` before push. CI runs both; local dev often catches only unit.
- **[release]** — branch `feature/<name>` off develop → PR → admin-merge. Bump VERSION on a separate `chore/vN.N.N-bump` PR before the develop→main release PR.
- **[CI diagnostics]** — when a test fails only in CI, add `printf 'RUN: %s\n' "$t" >&2` before each test function so the log pinpoints the failing one. Committed into tests/unit.sh runner.
- **[bash 3.2 parity]** — every array gets `=()` init; skip `mapfile`/`readarray`; no `${var,,}`/`${var^^}`; test on macOS first.
- **[commit messages]** — imperative subject + body that explains WHY; reference PR phase ("v1.6 Phase 1 of 3") so future greps reveal roadmap position.
- **[dogfooding]** — `.platform/` here is gitignored. Use `agentboard brief` at session start to see our own state, not to develop against.
- **[admin-merge]** — `gh pr merge <n> --merge --admin --delete-branch` bypasses reviewers for solo dev. Always pair with `git pull --ff-only` on develop after.
- **[watch/scheduler]** — run `agentboard watch --uninstall` before renaming the project directory; the scheduler label is baked from the slug at install time and uninstall can't find it if the dir moves.
- **[usage]** — always pass `--type` on checkpoints for attributable spend data: `agentboard checkpoint <slug> --type design|implementation|debug|audit|handoff`. Generic labels make `usage learn` blind.
- **[watch]** — `agentboard watch --once --quiet` runs one poll tick manually; use it to preview which files would trigger an auto-checkpoint before relying on the scheduler.
<!-- agentboard:playbook:end -->
