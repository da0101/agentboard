---
stream_id: stream-framework-audit
slug: framework-audit
type: investigation
status: done
agent_owner: codex
domain_slugs: [framework-audit]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/framework-audit
created_at: 2026-04-18
updated_at: 2026-04-18
closure_approved: true
---

# framework-audit

## Scope
- Audit Agentboard end to end as a product and codebase, not just the active daemon stream.
- Evaluate whether the framework meaningfully solves context sharing between different LLM CLIs.
- Assess automation quality across work tracking, checkpoints, hooks, daemon flow, and tests.
- Identify architectural, product, usability, and maintainability risks with concrete file references.
- Out of scope: implementing fixes or closing any stream in this pass.

## Done criteria
- [x] Full-framework audit completed against runtime code, `.platform/` process layer, and tests
- [x] Required standardized audit snapshot written into this stream file
- [x] Blunt qualitative verdict delivered on value, design quality, context sharing, and automation
- [x] `.platform/memory/log.md` appended
- [x] `decisions.md` updated if any architectural choices were made

## Key decisions
2026-04-18 — Audit tracked as a dedicated investigation stream — Prevents framework-level findings from being buried inside the daemon implementation stream.

## Resume state

- **Last updated:** 2026-04-18 — by codex
- **What just happened:** Completed the framework audit, validated tests, and anchored the standardized snapshot in this stream.
- **Current focus:** Awaiting user review of the verdict and priority fixes.
- **Next action:** User decides whether to keep iterating on the framework and which must-fix items to tackle first.
- **Blockers:** none

## Progress log

2026-04-18 20:31 — Completed full-framework audit. Unit suite passes in a clean env; integration passes. Main findings: multi-stream event attribution is incorrect, transient event data is commit-prone, and automation parity is still partial outside Claude hooks.

## Open questions
- Does the current automation meaningfully protect against human process drift outside Claude Code hooks?

---

## 🔍 Audit — 2026-04-18

# 📋 Agentboard Platform — Audit Snapshot

> **Stream:** `framework-audit` · **Date:** 2026-04-18 · **Status:** 🟡 Viable, useful, but not fully hardened
> **Repos touched:** `agentboard` (`repo-primary`)

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ agentboard |
|---|:---:|
| **Implementation** | 🟡 |
| **Tests**          | 🟡 |
| **Security**       | 🟡 |
| **Code Quality**   | 🟡 |

> **Bottom line:** Agentboard is a real and valuable work-state framework, but its cross-provider context sharing and automation guarantees are still partial, setup-sensitive, and leaky at the edges.

---

## 🔄 How the Feature Works (End-to-End)

```text
Claude / Codex / Gemini
        |
        v
root entry file / wrapper
        |
        +--> agentboard brief + handoff
        |         |
        |         v
        |   .platform/work/*.md
        |   .platform/domains/*.md
        |   .platform/memory/*.md
        |
        +--> checkpoint / watch / hooks
        |         |
        |         v
        |   Resume state + progress log
        |
        +--> event logger / session tracker
                  |
                  v
         daemon (optional) -> .platform/events.jsonl
                  |
                  v
           next provider reads shared state
```

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🟡 Medium | agentboard | Raw `PostToolUse` and `UserPromptSubmit` payloads are written unredacted to `.platform/events.jsonl`, and transient daemon/watch files also live under `.platform/`; in normal user repos these can be commit-prone because `init` scaffolds `.platform/` but does not install ignore rules for `events*.jsonl`, `.daemon-port`, `.file-locks.json`, or watch state. |
| 🟢 Clean | agentboard | No obvious hardcoded secrets, remote execution surface, or non-local daemon exposure were found in the inspected runtime paths; the daemon is loopback-only and built on Node built-ins. |

---

## 🧪 Test Coverage

### agentboard
| Area | Tested? | File |
|---|:---:|---|
| Stream lifecycle, checkpointing, handoff | ✅ Strong | `tests/unit/checkpoint_test.sh`, `tests/unit/close_test.sh`, `tests/unit/handoff_resume_test.sh`, `tests/unit/commands_streams_test.sh` |
| Daemon, events, rotation, locks | ✅ Good | `tests/unit/daemon_test.sh`, `tests/unit/events_test.sh`, `tests/unit/events_rotation_test.sh`, `tests/unit/lock_test.sh` |
| Watch/install/update/wrappers | ✅ Good | `tests/unit/watch_test.sh`, `tests/unit/watch_install_test.sh`, `tests/unit/install_hooks_test.sh`, `tests/unit/session_track_test.sh` |
| End-to-end project bootstrap and closure flow | ✅ Good | `tests/integration.sh` |
| Multi-stream event attribution and cross-stream correctness | 🔴 None | No direct coverage found; current tests assert only single-stream event tagging paths in `tests/unit/events_test.sh:31` |
| Test harness hermeticity for provider env fallbacks | 🟡 Thin | `tests/unit/checkpoint_usage_test.sh:130` fails if `AGENTBOARD_PROVIDER` is already exported in the shell |

---

## ✅ Implementation Status

### agentboard
| Component | Status | Location |
|---|:---:|---|
| Deterministic handoff packet and scoped load order | ✅ Done | `lib/agentboard/commands/streams.sh:312` |
| Resume-state checkpointing and progress-log trimming | ✅ Done | `lib/agentboard/commands/checkpoint.sh:138` |
| Session-start briefing and drift surfacing | ✅ Done | `lib/agentboard/commands/brief.sh:1` |
| Doctor validation and sync drift detection | ✅ Done | `lib/agentboard/commands/doctor.sh:22` |
| Codex/Gemini wrappers and session tracking | ✅ Done | `templates/platform/scripts/codex-ab:20`, `templates/platform/scripts/gemini-ab:20`, `templates/platform/scripts/session-track.sh:19` |
| Event daemon, query surface, and rotation | ✅ Done | `bin/agentboard-daemon.js:140`, `lib/agentboard/commands/events.sh:25` |
| File-locking across providers | ⚪ Deferred | `lib/agentboard/commands/lock.sh:22`, `templates/platform/scripts/hooks/pre-tool-use-lock.sh:43` |
| Correct multi-stream event attribution | ❌ Missing | `templates/platform/scripts/hooks/event-logger.sh:31` |

---

## 🔧 Open Issues

### 🔴 Must Fix (blocking)
| # | Repo | Issue |
|---|---|---|
| 1 | agentboard | `event-logger.sh` assigns events to the first non-closed stream it finds, so shared activity becomes wrong as soon as more than one stream is active. This directly weakens the framework’s core context-sharing claim. (`templates/platform/scripts/hooks/event-logger.sh:31`) |
| 2 | agentboard | Transient orchestration state is commit-prone: raw event payloads, daemon port state, and persisted file locks live under `.platform/` without a shipped ignore/update path for normal user repos. (`templates/platform/scripts/hooks/event-logger.sh:69`, `bin/agentboard-daemon.js:118`, `lib/agentboard/commands/init.sh:82`) |

### 🟡 Should Fix Soon
| # | Repo | Issue | Location |
|---|---|---|---|
| 1 | agentboard | Session bootstrap still looks for a legacy `## Next action` section instead of the current `## Resume state` format, so the advisory start-of-session summary can miss the actual next step. | `templates/platform/scripts/hooks/platform-bootstrap.sh:86` |
| 2 | agentboard | Parallel-edit safety is still fail-open on timeout or daemon failure, and Codex/Gemini remain honor-system only. The tool is useful here, but the guarantee is softer than the marketing. | `lib/agentboard/commands/lock.sh:31`, `templates/platform/scripts/hooks/pre-tool-use-lock.sh:43` |
| 3 | agentboard | Core behavior is concentrated in very large Bash files (`usage.sh`, `watch.sh`, `streams.sh`, `checkpoint.sh`), which increases maintenance and regression risk even with tests. | `lib/agentboard/commands/usage.sh:1`, `lib/agentboard/commands/watch.sh:1`, `lib/agentboard/commands/streams.sh:1`, `lib/agentboard/commands/checkpoint.sh:1` |
| 4 | agentboard | Unit tests are not fully hermetic with respect to provider env fallbacks; the suite failed until `AGENTBOARD_PROVIDER` was unset because checkpoint intentionally reads shell-level defaults. | `lib/agentboard/commands/checkpoint.sh:113`, `tests/unit/checkpoint_usage_test.sh:130` |
| 5 | agentboard | Full automation parity still depends on setup hygiene: `doctor` currently reports entry-file drift, missing git hooks, and missing wrapper aliases in this repo, which means the framework still relies on operator discipline to reach its best behavior. | `lib/agentboard/commands/doctor.sh:49`, `lib/agentboard/commands/install_hooks.sh:219` |

### ⚪ Known Limitations (document, not block)
| # | Limitation |
|---|---|
| 1 | Agentboard does not transfer chat history or tool-call memory between providers; it transfers shared files, resume state, and event breadcrumbs. README is honest about this. |
| 2 | Non-Claude providers infer edit activity via filesystem polling, so observability is coarser than native tool hooks. |
| 3 | Auto-checkpointing and wrapper behavior are strongest when one stream is active; multi-stream automation is still weaker than the single-stream happy path. |

---

## 🎯 Close Checklist / Priority Order

  □  1. 🐛  Give events an explicit stream identity instead of “first active stream wins”; add multi-stream tests.
  □  2. 🛡️  Add a first-class ignore strategy for transient runtime files (`events*.jsonl`, `.daemon-port`, `.file-locks.json`, `.watch*`) and document retention/redaction expectations.
  □  3. 🔍  Make `platform-bootstrap.sh` and wrapper/session code read the same canonical resume parser used by `handoff`.
  □  4. ⚡  Break up the 450-770 line Bash command files into smaller modules before the next major feature wave.
  □  5. ✅  Re-run the audit after the two must-fix items land; if the scorecard improves, remove this section and decide on stream closure.
