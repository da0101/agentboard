---
stream_id: stream-watch-install
slug: watch-install
type: feature
status: done
agent_owner: claude
domain_slugs: [commands]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/watch-install
created_at: 2026-04-17
updated_at: 2026-04-18
closure_approved: true
---

# watch-install

_Metadata rules: `stream_id` must be `stream-<slug>`, `slug` must match the filename, `status` must match `work/ACTIVE.md`, and `updated_at` should change whenever ownership or state changes._

## Scope

**In scope — v1.6 Phase 2:**
- New subcommand `agentboard watch --install` that creates a per-project scheduler running `agentboard watch --once` every 10 minutes
- macOS support: writes a user LaunchAgent at `~/Library/LaunchAgents/com.agentboard.<project-slug>.plist` + bootstraps via `launchctl`
- Linux support: writes a user systemd unit pair at `~/.config/systemd/user/agentboard-<project-slug>.{service,timer}` + enables via `systemctl --user`
- `agentboard watch --uninstall` tears it down cleanly (reverse of install)
- `agentboard watch --status` reports: installed? active? last-run timestamp
- Project slug derived from `basename "$PWD"` with kebab-case normalization
- Plist/unit log stdout+stderr to `~/.agentboard/watch-<slug>.log` for debuggability
- Tests: generated plist/unit content is asserted directly; uninstall removes exactly what install created; slug normalization; platform gating (macOS-only code skipped on Linux and vice versa)

**Out of scope:**
- Windows / WSL support (no launchd or systemd — separate story)
- Cron-based fallback (launchd/systemd are sufficient on their target platforms)
- Per-user system-wide daemons (we use user-level schedulers to avoid sudo)
- Auto-install at `agentboard init` time — the user opts in explicitly by running `watch --install`
- Restart-on-crash policies beyond what launchd/systemd offer by default

## Done criteria

- [ ] `agentboard watch --install` on macOS creates the plist, `launchctl print` shows it loaded
- [ ] `agentboard watch --install` on Linux creates the .service + .timer, `systemctl --user list-timers` shows it active
- [ ] `agentboard watch --uninstall` removes the plist/units and unloads them — no orphan files
- [ ] `agentboard watch --status` distinguishes: not-installed / installed-not-loaded / installed-and-active / loaded-but-file-missing
- [ ] Five design refinements applied (see Design section): XML-escape on `$PWD`, empty-slug guard, `AGENTBOARD_WATCH_HOME` env for test isolation, status "loaded-but-file-missing" branch, decisions + playbook seed at close.
- [ ] New unit test file `tests/unit/watch_install_test.sh` covers the 11 cases listed under Design → Tests needed
- [ ] `bash tests/unit.sh` passes locally AND on CI (bash 5 strict mode)
- [ ] `bash tests/integration.sh` passes
- [ ] Manual verification on macOS: install on this repo, wait 10 min, confirm a watch checkpoint fires on the `watch-install` stream itself (meta-test: the feature runs its own stream)
- [ ] `ab-review` skill run on the diff before PR — findings addressed
- [ ] `.platform/memory/log.md` appended by close
- [ ] `memory/decisions.md` updated with launchd+systemd platform decision row
- [ ] `memory/playbook.md` appended with the `launchctl bootstrap` vs `load` dance and the rename-directory-breaks-uninstall caveat
- [ ] `memory/gotchas.md` appended if anything bit us

## Key decisions

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-17 | Triage → feature / medium / medium | OS-gated subcommand, new shared watch.sh territory, launchctl + systemctl have no prior test coverage in this repo |
| 2026-04-17 | Opus 4.7 for design + review; Sonnet 4.6 acceptable for test writing | Design needs failure-mode reasoning; tests are enumeration-style |
| 2026-04-17 | Use launchd (macOS) + systemd user timer (Linux) — NOT cron | Cron requires crontab-merge (clobber risk); launchd/systemd handle coalescing natively; user-level avoids sudo |
| 2026-04-17 | Per-project unit, identity key = slug from `basename $PWD` | Multi-project on one machine coexists cleanly; install/uninstall derive same paths from same PWD |
| 2026-04-17 | Orthogonal to foreground `watch &` PID file | Different lifecycles — mixing state invites bugs |
| 2026-04-17 | Opt-in via explicit `--install` (NOT auto at `init` time) | User controls when scheduler starts running |
| 2026-04-17 | Ship no log rotation in v1.6 | Append-only; rotation deferred to BACKLOG as design-question v1.7+ |
| 2026-04-17 | Reinstall is declarative: `watch --install` overwrites existing scheduler config | Lowest-friction UX; install remains idempotent when interval or threshold changes |
| 2026-04-17 | Log maintenance stays out of v1.6; no `--truncate-log` flag yet | Keeps the release surface focused on scheduler correctness first |

## Design (ab-architect output, 2026-04-17)

**Design question:** How should `agentboard watch --install/--uninstall/--status` register a per-project OS scheduler that runs `watch --once` every N minutes, cleanly across macOS (launchd) and Linux (systemd)?

**Components (9 helpers in lib/agentboard/commands/watch.sh):**
1. `_watch_scheduler` — OS detection. Returns `launchd` / `systemd` / `unsupported`. Single source of cross-platform gating.
2. `_watch_project_slug` — deterministic kebab-case identity from `basename $PWD`. **Identity key** for every filename, label, unit, log path.
3. `_watch_agentboard_bin` — resolves absolute path to the agentboard CLI (schedulers don't have user PATH).
4. `_watch_log_path` — `$HOME/.agentboard/watch-<slug>.log`. Shared by all paths.
5. `_watch_install` — public entry. Validates prereqs, dispatches to platform-specific installer.
6. `_watch_install_launchd` — plist generator + `launchctl bootstrap` with `load` fallback.
7. `_watch_install_systemd` — `.service` + `.timer` generator + `systemctl --user enable --now`.
8. `_watch_uninstall` — symmetric cleanup, OS-gated. Idempotent — running when not installed is a friendly no-op.
9. `_watch_status` — reports install + live + log metadata. Distinguishes not-installed / installed-not-loaded / installed-and-active / loaded-but-file-missing.

Platform-specific code confined to helpers 6/7 and siblings. ONE `uname`-gate at each public entry point, not scattered through.

**Data flow:**

```
$PWD → _watch_project_slug → <slug>
                               ├─► launchd:  label = com.agentboard.<slug>
                               │             plist  = $HOME/Library/LaunchAgents/<label>.plist
                               ├─► systemd:  unit   = agentboard-<slug>
                               │             files  = $HOME/.config/systemd/user/<unit>.{service,timer}
                               └─► log       = $HOME/.agentboard/watch-<slug>.log

Install captures at install time (baked into generated file):
  - absolute agentboard binary path
  - absolute project dir (XML-escaped for plist, INI-safe for systemd)
  - interval * 60 seconds (launchd StartInterval) / interval minutes (systemd OnUnitActiveSec)
  - threshold (passed to `watch --once --threshold N --quiet`)
  - log path (StandardOut/Err)

Uninstall: rederive <slug> from same $PWD → same label/unit → bootout/disable → rm.
```

**Invariants (testable):**
1. Slug determinism — same PWD → same slug
2. Slug safety — output matches `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` or is empty; no `/`, `..`, shell metachars, whitespace
3. Symmetry — install + uninstall in same PWD leaves filesystem byte-identical to pre-install
4. No PATH dependency — generated plist/unit uses absolute agentboard path
5. No silent clobber — existing unit is refreshed via bootout→bootstrap or fails loudly
6. Status truthfulness — never reports "active" when scheduler wouldn't actually fire
7. Orthogonality — `.platform/.watch.pid` (foreground) and launchd/systemd install share no state

**Failure modes:**

| Failure | Detection | Recovery |
|---|---|---|
| Unsupported OS | `_watch_scheduler` returns `unsupported` | `die` with "macOS/Linux only" |
| Empty slug (PWD=/) | Post-normalization length check | `die` — refuse to install |
| Binary unresolvable | `AGENTBOARD_ROOT` missing AND `command -v` fails | `die` with install instruction |
| `launchctl bootstrap` fails (SIP, older macOS) | Non-zero exit | Fallback to `launchctl load`; if still fails, warn + leave plist + exit 1 |
| `systemctl --user` fails (no D-Bus) | Non-zero exit | Warn with exact manual enable command; leave units |
| Conflicting unit loaded | Unconditional `bootout/disable \|\| true` before bootstrap | Idempotent reinstall |
| Partial install (file written, load failed) | Installer returns non-zero | `--uninstall` still removes file regardless of load state |
| Plist deleted out-of-band but still loaded | `launchctl print` shows loaded + file missing | `--status` reports "loaded-but-file-missing"; `--uninstall` runs bootout anyway |
| PWD changed between install and uninstall | Slug differs → different label | `--uninstall` reports "no unit for this project (slug=X)", exit 0 |
| Path injection via PWD (< > & in dir name) | XML-escape + regex-sanitized slug | Slug is always safe for filenames; PWD gets XML-escaped before plist injection |

**Cross-cutting concerns:**
- Auth: N/A (user-owned dirs only, no sudo)
- Tenant isolation: per-project slug ⇒ collision-free on one machine
- Logging: append-only `$HOME/.agentboard/watch-<slug>.log`; no rotation in v1.6
- Secrets: none
- Backpressure: launchd `StartInterval` coalesces misses; systemd `OnUnitActiveSec` measures from last completion — no overlap possible
- Testability hook: `AGENTBOARD_WATCH_HOME` env (falls back to `$HOME`) lets tests redirect install into a temp dir without polluting real `~/Library/LaunchAgents`

**Five refinements vs. existing draft:**
1. XML-escape `$PWD` before plist injection
2. Empty-slug guard in `_watch_install`
3. `AGENTBOARD_WATCH_HOME` env var for test isolation
4. "loaded-but-file-missing" branch in `_watch_status`
5. Seed decisions.md + playbook.md rows at close

**Tests needed (covered by new `tests/unit/watch_install_test.sh`):**
1. Slug normalization: `My Project!` → `my-project`; `/tmp` → `tmp`; `.foo` → `foo`; `/` → empty → install refuses
2. Happy path launchd (stub `_watch_scheduler` → `launchd`): plist generated with absolute bin + project dir + interval*60
3. Happy path systemd (stub → `systemd`): .service + .timer with correct `OnUnitActiveSec`
4. Idempotent reinstall: run twice, same final state, no error
5. Symmetric uninstall: snapshot AGENTBOARD_WATCH_HOME, install, uninstall, diff → empty
6. Uninstall when not installed: exit 0, friendly message
7. Install fails on unsupported OS (stub uname)
8. Install fails on empty slug
9. Install fails when agentboard bin unresolvable
10. Status distinguishes 3 states (not-installed / installed-not-loaded / active)
11. Content check: plist with `<` in PWD parses cleanly (plutil -lint / xmllint)

**Rejected alternatives (8):**
cron (crontab-merge risk) · nohup watch & (no reboot survival) · single global scheduler entry (discovery loop complexity) · system-wide units in /etc (sudo) · shared PID state with foreground (lifecycle mismatch) · structured plist writer (overkill) · auto-install at init (violates opt-in) · cron + flock (dated)

**Open questions — BLOCKING execution until user answers:**
_Resolved on 2026-04-17 by implementation-owner decision delegated by the user._
- Reinstall with different `--interval` => silently overwrite existing scheduler config.
- Log rotation => ship nothing in v1.6; defer log-maintenance UX to backlog / later design.

## STRICT PROTOCOL for the next agent (Codex / Claude / Gemini) — READ FIRST

You are resuming mid-stream AFTER design, BEFORE execution. You MUST follow every rule below. Deviations require user approval in chat.

### Hard rules (non-negotiable)

- **MUST** run `agentboard handoff watch-install` as your first action before touching any code.
- **MUST** read the entire "Design" section above before writing code. The design is locked.
- **MUST NOT** re-design or propose alternative approaches. The 8 rejected alternatives have already been considered.
- **MUST NOT** `git commit` without explicit user approval (Claude Code's bash-guard hook will prompt; Codex/Gemini: ASK the user in chat).
- **MUST NOT** `git push` without the user's go-ahead.
- **MUST NOT** skip test writing. All 11 test cases in Design → Tests needed are required, not optional.
- **MUST NOT** edit any file outside `lib/agentboard/commands/watch.sh`, `tests/unit/watch_install_test.sh`, `lib/agentboard/commands/help.sh`, `CHEATSHEET.md`, `.platform/memory/decisions.md`, `.platform/memory/playbook.md`, `.platform/memory/log.md` without user approval.
- **MUST** checkpoint at every step boundary below (after steps 2, 4, 6, 8).
- **MUST** run `bash tests/unit.sh` AND `bash tests/integration.sh` locally before committing. Both must PASS.
- **MUST** operate on branch `feature/watch-install` (already created off `develop`). If you're on a different branch, `git checkout feature/watch-install` before step 1.
- **MUST** update this stream file's `## Key decisions` table with any new decision you make (e.g., if you resolve an open question).

### Step-by-step (execute IN ORDER; do NOT skip)

**STEP 0 — Confirm unblocking**

The 2 open questions below (under `## Open questions`) BLOCK execution. If the user has not answered both in chat:
- **MUST** ask the user explicitly, quoting both questions.
- **MUST NOT** assume the defaults — the defaults are my recommendation, but the user has not confirmed.
- If user says "go with defaults" or "go", record that as a decision row in `## Key decisions` and continue.

Acceptance: both questions answered. Decisions appended. Proceed to Step 1.

**STEP 1 — Apply the 5 refinements to `lib/agentboard/commands/watch.sh`**

The existing draft in that file is ~90% correct. Apply EXACTLY these 5 deltas:

1. **XML-escape PWD** — before injecting `$project_dir` into the plist heredoc in `_watch_install_launchd`, run it through a small escape helper that replaces `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. New helper: `_watch_xml_escape` in watch.sh.
2. **Empty-slug guard** — at the top of `_watch_install`, after computing `slug`, `die` with "Could not derive a project slug from PWD ($PWD). Rename the directory to contain at least one alphanumeric character." if `[[ -z "$slug" ]]`.
3. **`AGENTBOARD_WATCH_HOME` env override** — introduce a helper `_watch_home` that returns `${AGENTBOARD_WATCH_HOME:-$HOME}`. Replace every `$HOME/Library/LaunchAgents`, `$HOME/.config/systemd/user`, and `$HOME/.agentboard/watch-*.log` with `$(_watch_home)/...`. Tests set `AGENTBOARD_WATCH_HOME` to a temp dir.
4. **`_watch_status` loaded-but-file-missing branch** — on launchd path, if `launchctl print` shows loaded AND plist file does NOT exist, report: `Installed: no — but service is still loaded (orphan). Run: launchctl bootout gui/$(id -u)/<label>`. Same spirit on systemd: check `is-active` vs file existence.
5. **Harvest seed** — do NOT inline; this happens at `close` harvest (Step 5). Just make sure the done-criteria entries for decisions.md and playbook.md are in the checklist.

Acceptance: `bash -n lib/agentboard/commands/watch.sh` passes. Manual `agentboard watch --install` on the current project works. Manual `agentboard watch --status` reports correctly.

**Checkpoint after Step 1:**
```
agentboard checkpoint watch-install \
  --what "Applied 5 design refinements to watch.sh: xml-escape, empty-slug guard, AGENTBOARD_WATCH_HOME, status-orphan branch, harvest checklist" \
  --next "Write tests/unit/watch_install_test.sh covering the 11 cases" \
  --focus "tests/unit/watch_install_test.sh" \
  --provider <your-provider> --model <your-model> \
  --cumulative-in N --cumulative-out N --complexity normal
```

**STEP 2 — Write `tests/unit/watch_install_test.sh`**

Model: Sonnet 4.6 is sufficient (enumeration-style test generation). Cover exactly the 11 cases in Design → Tests needed.

Rules:
- MUST use `AGENTBOARD_WATCH_HOME="$(mktemp -d)"` to isolate each test
- MUST NOT touch `~/Library/LaunchAgents` or `~/.config/systemd/user` anywhere
- MUST stub `_watch_scheduler` where platform-specific behavior is under test
- MUST mirror existing test-file style in `tests/unit/` (e.g. `watch_test.sh`, `install_hooks_test.sh`): `set -euo pipefail`, source `helpers.sh`, `RUN:` prefix per sub-test, final for-loop dispatcher
- MUST guard empty arrays with `=()` init (bash 3.2 / 5 strict mode)
- MUST NOT use `head -N` in a pipeline (SIGPIPE under pipefail — use `awk 'NR<=N'` or for-loop with break)
- MUST NOT use `printf '-...'` — format strings starting with `-` are treated as flags; use `printf '%s\n' '-content'`

Acceptance: `bash tests/unit/watch_install_test.sh` exits 0 on macOS. All 11 named tests print `RUN: ...` lines.

**Checkpoint after Step 2.**

**STEP 3 — Update docs**

- `lib/agentboard/commands/help.sh` — confirm `watch` entry documents `--install / --uninstall / --status` and the `AGENTBOARD_WATCH_HOME` env override. Add one line if missing.
- `CHEATSHEET.md` — add a block under the existing watch section showing the install/uninstall/status trio.

Acceptance: `agentboard watch --help` output references the three new flags.

**STEP 4 — Run full test suite**

```bash
bash tests/unit.sh
bash tests/integration.sh
```

MUST both print `PASS`. If either fails, fix before proceeding. DO NOT commit a failing suite.

**Checkpoint after Step 4** with what tests pass.

**STEP 5 — `ab-review` the diff**

Invoke the `ab-review` skill on the diff between `feature/watch-install` and `develop`. Specifically check:
- Path injection — is `$PWD` properly escaped before going into plist XML?
- Command-injection — is the slug regex-sanitized before becoming a filename?
- launchctl / systemctl calls — are they safely quoted? No `eval`, no unquoted `$slug`?
- Test coverage — are all 11 test cases from the design actually in the test file?

Address every `high`/`medium` finding before proceeding.

**STEP 6 — Commit**

MUST ask user approval first. Commit message format:
```
watch: --install / --uninstall / --status (v1.6 Phase 2)

<1-3 paragraph body explaining what shipped, referencing stream slug
 watch-install and the 9 helpers / 5 refinements / 11 tests.>
```

**STEP 7 — PR + CI + merge**

```bash
git push -u origin feature/watch-install
gh pr create --base develop --title "watch: --install / --uninstall / --status (v1.6 Phase 2)" --body "<use stream summary>"
gh pr checks <N> --watch        # MUST wait for green
gh pr merge <N> --merge --admin --delete-branch
git checkout develop && git pull --ff-only
```

MUST NOT merge without green CI.

**STEP 8 — Close the stream (harvest ritual)**

```bash
agentboard close watch-install   # prints harvest checklist
```

Then:
- Append 1–3 rows to `.platform/memory/decisions.md` — at minimum the "launchd + systemd user-level, not cron" decision row
- Append 1–3 rows to `.platform/memory/playbook.md` — at minimum: "rename project dir after `watch --install` breaks uninstall — run `--uninstall` before rename, or remove the plist/units manually"
- Append gotchas if any new bash-isms bit you
- Append an entry to `.platform/memory/log.md` — automatic via close

Then:
```bash
agentboard close watch-install --confirm
```

**STEP 9 — Update roadmap**

Mark task #51 completed. Phase 2 done. Phase 3 (post-commit Progress log hook) is next.

### Models per step (per triage)

| Step | Skill | Model |
|---|---|---|
| 1 (refinements) | direct execute | Opus 4.7 OR Sonnet 4.6 (code-level precision; either works) |
| 2 (tests) | `ab-test-writer` | Sonnet 4.6 sufficient |
| 5 (review) | `ab-review` | Opus 4.7 (security-adjacent) |
| 8 (harvest) | direct execute | Sonnet 4.6 sufficient (distillation) |

## Resume state
_Overwritten by `agentboard checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-04-17 by danilulmashev
- **What just happened:** (auto-watch) 9 file(s) modified since 23:42: AGENTS.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh, lib/agentboard/commands/install_hooks.sh, templates/root/AGENTS.md.template
- **Current focus:** AGENTS.md
- **Next action:** Run one non-sandbox timed-fire macOS check, then re-audit for closure readiness.
- **Blockers:** none

## Progress log
_Append-only. `agentboard checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `2026-04-17 HH:MM — <what happened>`._

2026-04-17 23:42 — (auto-watch) 9 file(s) modified since 23:42: AGENTS.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh, lib/agentboard/commands/install_hooks.sh, templates/root/AGENTS.md.template

2026-04-17 23:02 — (auto-watch) 7 file(s) modified since 23:02: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 22:52 — (auto-watch) 7 file(s) modified since 22:52: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 22:42 — (auto-watch) 7 file(s) modified since 22:42: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 19:47 — (auto-watch) 7 file(s) modified since 19:47: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 19:37 — (auto-watch) 7 file(s) modified since 19:37: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 19:27 — (auto-watch) 7 file(s) modified since 19:27: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 18:46 — (auto-watch) 7 file(s) modified since 18:46: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 17:47 — (auto-watch) 7 file(s) modified since 17:47: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/doctor.sh, lib/agentboard/commands/init.sh

2026-04-17 16:11 — (auto-watch) 6 file(s) modified since 16:11: CLAUDE.md, GEMINI.md, README.md, lib/agentboard/commands/init.sh, lib/agentboard/commands/install_hooks.sh

## Open questions — BLOCKING execution
_Resolved on 2026-04-17. Reinstall is declarative overwrite, and log maintenance remains deferred to backlog for a later release._

---

## 🔍 Audit — 2026-04-17

> Supersedes previous audit. Run via Stream / Feature Analysis Protocol — 1 repo direct analysis pass after implementation, tests, and manual macOS command verification.

# 📋 watch-install — Audit Snapshot

> **Stream:** `watch-install` · **Date:** 2026-04-17 · **Status:** 🟡 Shippable, with one environment-limited verification gap
> **Repos touched:** repo-primary

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ repo-primary |
|---|:---:|
| **Implementation** | 🟡 |
| **Tests**          | 🟢 |
| **Security**       | 🟢 |
| **Code Quality**   | 🟢 |

> **Bottom line:** the scheduler feature now matches the locked design, passes the full automated suite, and manually verifies `install` / `status` / `uninstall` on macOS; the remaining yellow is that timed background execution could not be fully proven inside this sandboxed workspace.

---

## 🔄 How the Feature Works (End-to-End)

```text
agentboard watch --install
  -> derive slug from $PWD
  -> resolve absolute agentboard binary path
  -> write launchd plist OR systemd unit files under HOME/AGENTBOARD_WATCH_HOME
  -> scheduler runs: agentboard watch --once --quiet --threshold N
  -> watch --status reports installed / active / orphan state
  -> watch --uninstall tears down the scheduler and removes empty support dirs
```

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🟢 Clean | repo-primary | XML values are escaped before plist generation, systemd executable paths are quoted, and no `eval`, secrets, or network surfaces were introduced. Reviewed in `lib/agentboard/commands/watch.sh:296`, `lib/agentboard/commands/watch.sh:304`, `lib/agentboard/commands/watch.sh:347`. |

---

## 🧪 Test Coverage

### repo-primary
| Area | Tested? | File |
|---|:---:|---|
| Foreground watch polling (`--once`, `--stop`, auto-detect) | ✅ Good | `tests/unit/watch_test.sh:40` |
| Scheduler install / uninstall / status / escaping / idempotence | ✅ Strong | `tests/unit/watch_install_test.sh:133` |
| Top-level help/catalog sync for scheduler flags | ✅ Good | `tests/unit/commands_help_test.sh:8` |
| Full regression signal | ✅ Good | `bash tests/unit.sh`, `bash tests/integration.sh` |

---

## ✅ Implementation Status

### repo-primary
| Component | Status | Location |
|---|:---:|---|
| Existing foreground watch loop | ✅ Done | `lib/agentboard/commands/watch.sh:1` |
| New flag parsing for `--install`, `--uninstall`, `--status` | ✅ Done | `lib/agentboard/commands/watch.sh:4` |
| launchd install path with load verification | ✅ Done | `lib/agentboard/commands/watch.sh:347` |
| systemd install path with quoted executable path | ✅ Done | `lib/agentboard/commands/watch.sh:416` |
| uninstall / status plumbing, including orphan reporting | ✅ Done | `lib/agentboard/commands/watch.sh:453` |
| XML escape helper, empty-slug guard, `AGENTBOARD_WATCH_HOME` | ✅ Done | `lib/agentboard/commands/watch.sh:292`, `lib/agentboard/commands/watch.sh:327` |
| Scheduler-specific unit tests | ✅ Done | `tests/unit/watch_install_test.sh:133` |
| Top-level help, watch help, and cheatsheet updates | ✅ Done | `lib/agentboard/commands/help.sh:79`, `lib/agentboard/commands/watch.sh:107`, `CHEATSHEET.md:73` |
| Stream brief accuracy | ✅ Done | `.platform/work/BRIEF.md:13` |

---

## 🔧 Open Issues

### 🔴 Must Fix (blocking)
| # | Repo | Issue |
|---|---|---|
| none | — | — |

### 🟡 Should Fix Soon
| # | Repo | Issue | Location |
|---|---|---|---|
| 1 | repo-primary | The timed self-dogfooding meta-test could not be proven inside this sandbox: the launchd child logged `Operation not permitted` when trying to execute the repo-local binary from the sandboxed workspace. Verify one real scheduled fire in a normal user shell before declaring the stream fully closed. | `/tmp/agentboard-watch-meta.4eiPFu/.agentboard/watch-agentboard.log` |

### ⚪ Known Limitations (document, not block)
| # | Limitation |
|---|---|
| 1 | Windows / WSL support is intentionally out of scope for this stream. |
| 2 | Log maintenance is intentionally deferred to backlog after scheduler correctness. |
| 3 | Linux runtime behavior is implemented and unit-tested, but was not live-run in a real user-systemd session in this environment. |

---

## 🎯 Close Checklist / Priority Order

  □  1. 🔍  Run one non-sandbox macOS timed-fire check so the launchd job proves it can execute the repo binary outside this workspace restriction.
  □  2. 🧪  If a Linux user-systemd environment is available, run one `--install` / `--status` / `--uninstall` smoke test there.
  □  3. ✅  Re-run this audit after those environment-level checks; if clean, remove the audit section and move to stream closure.
