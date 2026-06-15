---
stream_id: stream-silicon-valley-mindset
slug: silicon-valley-mindset
type: chore
status: done
agent_owner: codex
domain_slugs: [product-engineering-mindset]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/silicon-valley-mindset
created_at: 2026-06-14
updated_at: 2026-06-14
closure_approved: true
---

# silicon-valley-mindset

## Scope
- Add a durable process rule that PM and engineering agents should think like leading Silicon Valley product teams: ambitious, future-facing, innovative, user-obsessed, craft-driven, and execution-minded.
- Place the rule where future Claude, Codex, and Gemini sessions will actually read it during normal work.
- Keep it practical: encourage product ambition and high standards without causing scope creep, unapproved feature expansion, or vague hype.

## Done criteria
- [x] New stream and domain registered.
- [x] Isolated feature worktree exists and local environment recorded.
- [x] Compact local research identifies the right shipped template/process files to update.
- [x] Plan approved before implementation.
- [x] Mindset rule added to shipped process/role templates and current runtime copies as needed.
- [x] Tests or contract checks cover the new rule where appropriate.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if this becomes a durable process decision.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-14 — Encode the Silicon Valley product mindset in workflow, role, and root-entry templates — the owner wants the standard to influence normal PM/engineering work across Claude, Codex, and Gemini, while explicit guardrails prevent scope creep.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-silicon-valley-mindset` | `feature/silicon-valley-mindset` | `origin/main` | no install needed; bash CLI with shell tests | focused shell contract tests | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-14 by danilulmashev
- **What just happened:** Implemented the Silicon Valley product mindset rule across workflow, role templates/live roles, root templates/live entries, memory, and contract tests.
- **Current focus:** —
- **Next action:** User reviews the change; focused tests pass, full unit suite still has unrelated daemon startup failures to decide whether to investigate.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-14 19:11 — Implemented the Silicon Valley product mindset rule across workflow, role templates/live roles, root templates/live entries, memory, and contract tests.

2026-06-14 18:44 — Completed compact local and external research and proposed the template/test implementation plan for approval.

2026-06-14 00:00 — Registered Silicon Valley product-engineering mindset stream and domain.
2026-06-14 00:00 — Added mindset rule to workflow, role templates/live copies, root templates/live entries, memory, and contract tests.

## Open questions
_Things blocked on user input. Remove when resolved._

None.

---

## 🔍 Audit — 2026-06-14

> Run via Stream / Feature Analysis Protocol — local read-only audit. Sub-agent dispatch was not used because the available multi-agent tool only permits spawning when the user explicitly asks for sub-agents.

# 📋 silicon-valley-mindset — Audit Snapshot

> **Stream:** `silicon-valley-mindset` · **Date:** 2026-06-14 · **Status:** 🟢 awaiting-verification
> **Repos touched:** `repo-primary`

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ repo-primary |
|---|:---:|
| **Implementation** | 🟢 |
| **Tests**          | 🟢 |
| **Security**       | 🟢 |
| **Code Quality**   | 🟢 |

> **Bottom line:** The mindset rule is implemented across workflow, role, and entry templates with guardrails and contract tests; full unit suite is green when run with local daemon socket permissions.

---

## 🔄 How the Feature Works (End-to-End)

```
Agent starts
  -> root entry file points to workflow/roles
  -> workflow defines Silicon Valley product mindset globally
  -> role index makes the mindset a baseline
  -> PM/feature/MVP roles apply role-specific ambition + guardrails
  -> contract test prevents accidental removal from shipped/live surfaces
```

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🟢 Clean | repo-primary | Docs/templates/test-only change. Secret/risky-pattern grep found no secrets, eval, console logging, tokens, or executable command construction in the changed surfaces. |

---

## 🧪 Test Coverage

### repo-primary
| Area | Tested? | File |
|---|:---:|---|
| Mindset appears in workflow, roles, root templates, and live entries | ✅ Strong | `tests/unit/product_mindset_contract_test.sh` |
| Workflow contracts still intact | ✅ Strong | `tests/unit/workflow_contract_test.sh` |
| Role pack contracts still intact | ✅ Strong | `tests/unit/roles_pack_test.sh` |
| Entry template handoff contracts still intact | ✅ Strong | `tests/unit/entry_templates_handoff_test.sh` |
| Full unit suite | ✅ Strong | `bash tests/unit.sh` → `PASS: unit (49 files, 390 tests)` |

---

## ✅ Implementation Status

### repo-primary
| Component | Status | Location |
|---|:---:|---|
| Global workflow rule | ✅ Done | `templates/platform/workflow.md:16`, `.platform/workflow.md:16` |
| Role baseline inheritance | ✅ Done | `templates/platform/roles/INDEX.md:7`, `.platform/roles/INDEX.md:7` |
| PM role application | ✅ Done | `templates/platform/roles/product-manager.md:20`, `.platform/roles/product-manager.md:20` |
| Feature engineer role application | ✅ Done | `templates/platform/roles/feature-builder.md:20`, `.platform/roles/feature-builder.md:20` |
| Startup MVP role application | ✅ Done | `templates/platform/roles/startup-mvp.md:19`, `.platform/roles/startup-mvp.md:19` |
| Root entry template exposure | ✅ Done | `templates/root/AGENTS.md.template:39`, `templates/root/CLAUDE.md.template:45`, `templates/root/GEMINI.md.template:37` |
| Current repo entry exposure | ✅ Done | `AGENTS.md:28`, `CLAUDE.md:125`, `GEMINI.md:122` |
| Durable process decision | ✅ Done | `.platform/memory/decisions.md:48` |
| Stream/domain registration | ✅ Done | `.platform/work/silicon-valley-mindset.md:1`, `.platform/domains/product-engineering-mindset.md:1` |
| Contract test | ✅ Done | `tests/unit/product_mindset_contract_test.sh:10` |

---

## 🔧 Open Issues

### 🔴 Must Fix (blocking)
| # | Repo | Issue |
|---|---|---|
| — | — | None |

### 🟡 Should Fix Soon
| # | Repo | Issue | Location |
|---|---|---|---|
| — | — | None |

### ⚪ Known Limitations (document, not block)
| # | Limitation |
|---|---|
| 1 | Daemon-dependent tests require permission to bind `127.0.0.1`; sandboxed runs fail with `listen EPERM`, while elevated/local runs pass. |

---

## 🎯 Close Checklist / Priority Order

  ☑  1. 🧪  Run focused contract suites.
  ☑  2. 🧪  Run full unit suite with local daemon socket permission.
  ☑  3. 🔍  Confirm no blocking implementation, test, security, or quality issues.
  □  4. ✅  Commit, push, merge, tag, and release after audit.
