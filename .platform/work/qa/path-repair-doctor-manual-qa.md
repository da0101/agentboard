# Manual QA - path-repair-doctor

## Scope

Validate that Agentboard can repair stale generated path references from older projects, especially `.claude/roles/*` references in root entry files that should now point to `.platform/roles/*`.

## Environment

- Branch: `develop`
- Commands under test: `ab repair`, `ab repair --dry-run`, `ab doctor --repair`
- Fixture type: temporary project initialized with `ab init`

## Safety Limits

- Do not run repair against unrelated worktrees with unsaved user edits unless using `--dry-run`.
- Repair is expected to rewrite only known safe path mappings.
- Runtime artifacts such as `agentboard.hud-status.json` must remain ignored and uncommitted.

## Manual Steps

1. Create a temporary project and initialize Agentboard.
2. Write `CLAUDE.md` with stale references to `.claude/roles/INDEX.md` and `.claude/roles/debugger.md`.
3. Run `ab repair --dry-run`.
4. Confirm output flags the stale path and leaves `CLAUDE.md` unchanged.
5. Run `ab repair`.
6. Confirm `CLAUDE.md` now contains `.platform/roles/INDEX.md` and `.platform/roles/debugger.md`.
7. Confirm `.gitignore` contains `agentboard.hud-status.json`.
8. Run `ab doctor --repair --dry-run`.
9. Confirm it delegates to the same repair scan.

## Automated Evidence

- `bash tests/unit/commands_repair_test.sh`
- `bash tests/unit/commands_doctor_test.sh`
- `bash tests/unit/commands_update_test.sh`
- `bash tests/unit/file_size_ratchet_test.sh`
- `npm test`
- `bin/ab repair --dry-run`
- `bin/ab doctor --repair --dry-run`
- `bin/ab validate --ci`
- `bin/ab doctor --ci`

## Expected Result

- Stale `.claude/roles` references are repaired to `.platform/roles`.
- Dry-run mode reports drift without writing files.
- `doctor --repair` uses the same repair path.
- The repair command runs `ab update`, `ab doctor --ci`, and `ab validate --ci` in apply mode.
- Runtime HUD snapshots are ignored by the runtime block.

## Signoff

Automated checks passed locally on 2026-06-26. `bin/ab doctor --ci` still reports the existing legacy multi-stream BRIEF warning in this repo; that warning predates this change and does not block the repair command.
