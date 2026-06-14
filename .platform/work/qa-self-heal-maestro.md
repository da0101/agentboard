---
stream_id: stream-qa-self-heal-maestro
slug: qa-self-heal-maestro
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [qa-self-heal]
repo_ids: [repo-primary]
base_branch: main
git_branch: feature/qa-self-heal-maestro
created_at: 2026-06-14
updated_at: 2026-06-14
closure_approved: false
---

# qa-self-heal-maestro

## Scope
- Add Agentboard capability for agent-driven QA loops that can use Maestro-style app automation to click, drill, stress limits, collect evidence, and feed reports back into the coding agent.
- Define safety guardrails for backend/API/load/rate-limit testing, third-party calls, destructive data, and self-healing scope.
- Add the right reusable skill and/or role so Claude, Codex, and Gemini route “run deep manual QA / stress the app / self-heal findings” consistently.
- Integrate report ingestion and stop conditions: what to fix automatically, what to escalate, when to stop, and how to summarize residual risk.
- Out of scope until approved: implementing project-specific Maestro flows for `cashflow-guard`, running load tests against production, or adding hard dependencies that every Agentboard project must install.

## Done criteria
- [x] New stream and domain registered.
- [x] Isolated feature worktree exists and local environment recorded.
- [x] Research-backed plan approved by the user before implementation.
- [x] QA self-heal skill/role/workflow docs added to shipped templates and provider runtime copies where applicable.
- [x] Tests cover role/skill/template integrity and any changed init/update behavior.
- [x] Verification demonstrates the capability is discoverable in a fresh Agentboard project.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if the implementation locks durable behavior.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

2026-06-14 — Add a dedicated `qa-automation-engineer` role plus `ab-qa-self-heal` skill — The existing `qa-engineer` role is intentionally read-only and independent; self-healing QA needs a separate bounded automation identity with explicit safety gates.
2026-06-14 — Treat Maestro as optional project capability, not a required Agentboard dependency — Projects can expose Maestro MCP/CLI wrappers when they have mobile/app QA, while Agentboard remains stack-agnostic and dependency-light.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/private/tmp/agentboard-qa-self-heal` | `feature/qa-self-heal-maestro` | `origin/main` | no install needed; bash CLI with shell tests | focused `bash tests/unit/*_test.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-14 by danilulmashev
- **What just happened:** Implemented ab-qa-self-heal, qa-automation-engineer, provider/template routing, memory decision/log entries, and contract tests; focused tests pass, full aggregate unit reproduces daemon-start race only.
- **Current focus:** —
- **Next action:** User reviews changes; if accepted, ask explicitly before commit/push/release. Do not close/archive until user approves stream closure.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-14 18:04 — Implemented ab-qa-self-heal, qa-automation-engineer, provider/template routing, memory decision/log entries, and contract tests; focused tests pass, full aggregate unit reproduces daemon-start race only.

2026-06-14 16:37 — Registered qa-self-heal-maestro stream/domain, researched Agentboard role/skill patterns, cashflow-guard Maestro usage, and official Maestro MCP/flow/report docs.

2026-06-14 00:00 — Added `ab-qa-self-heal`, `qa-automation-engineer`, routing/docs/install contracts, and verification tests.

2026-06-14 00:00 — Registered QA self-heal/Maestro stream and domain.

## Open questions
_Things blocked on user input. Remove when resolved._

None.

---

## 🔍 Audit — 2026-06-14

> Supersedes previous audit placeholder. Run via Stream / Feature Analysis Protocol — 1 read-only repo audit.

# 📋 qa-self-heal-maestro — Audit Snapshot

> **Stream:** `qa-self-heal-maestro` · **Date:** 2026-06-14 · **Status:** 🟢 awaiting-verification
> **Repos touched:** repo-primary (`agentboard`)

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ agentboard |
|---|:---:|
| **Implementation** | 🟢 |
| **Tests**          | 🟢 |
| **Security**       | 🟢 |
| **Code Quality**   | 🟢 |

> **Bottom line:** QA self-heal is implemented as a provider-neutral, bounded role+skill capability with install/routing contracts and no blocking findings.

---

## 🔄 How the Feature Works (End-to-End)

```
User asks for deep app QA / Maestro / self-heal
  -> .platform/roles/INDEX.md routes intent to qa-automation-engineer
  -> ab-qa-self-heal protocol selects project drivers
  -> agent runs bounded QA loop, captures evidence, fixes safe defects
  -> report + manual QA plan describe runs, fixes, residual risk, and stop reason
```

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🟢 Clean | agentboard | No secrets, auth changes, dependency additions, shell execution changes, or production-touching code paths introduced. Safety gates explicitly forbid uncapped production/third-party stress at `templates/skills/ab-qa-self-heal/SKILL.md:54`, `templates/skills/ab-qa-self-heal/SKILL.md:60`, and `templates/skills/ab-qa-self-heal/SKILL.md:204`. |

---

## 🧪 Test Coverage

### agentboard
| Area | Tested? | File |
|---|:---:|---|
| Skill safety/Maestro/report contract | ✅ Strong | tests/unit/qa_self_heal_contract_test.sh:10 |
| Role routing to self-heal skill | ✅ Strong | tests/unit/qa_self_heal_contract_test.sh:42 |
| Fresh init installs provider copies | ✅ Strong | tests/unit/qa_self_heal_contract_test.sh:71 |
| Role pack inventory | ✅ Strong | tests/unit/roles_pack_test.sh:14 |
| Role command/update behavior | ✅ Strong | tests/unit/commands_role_test.sh:10 |
| Current verification | ✅ Good | Focused tests pass; aggregate `bash tests/unit.sh` reproduces unrelated daemon-start race in daemon-dependent files only, while those files pass individually. |

---

## ✅ Implementation Status

### agentboard
| Component | Status | Location |
|---|:---:|---|
| `ab-qa-self-heal` shipped skill | ✅ Done | templates/skills/ab-qa-self-heal/SKILL.md:1 |
| Claude/Codex/Gemini installed skill copies | ✅ Done | .claude/skills/ab-qa-self-heal/SKILL.md:1 / .agents/skills/ab-qa-self-heal/SKILL.md:1 |
| `qa-automation-engineer` role | ✅ Done | templates/platform/roles/qa-automation-engineer.md:1 |
| Runtime role copy | ✅ Done | .platform/roles/qa-automation-engineer.md:1 |
| Role routing | ✅ Done | templates/platform/roles/INDEX.md:43 |
| Role+skill stacking guidance | ✅ Done | templates/platform/roles/INDEX.md:61 |
| Skill label map | ✅ Done | templates/platform/agents/skill-labels.md:21 |
| Root/provider skill lists | ✅ Done | AGENTS.md:163 |
| Durable decision | ✅ Done | .platform/memory/decisions.md:47 |

---

## 🔧 Open Issues

### 🔴 Must Fix (blocking)
| # | Repo | Issue |
|---|---|---|
| — | — | None |

### 🟡 Should Fix Soon
| # | Repo | Issue | Location |
|---|---|---|---|
| — | — | None | — |

### ⚪ Known Limitations (document, not block)
| # | Limitation |
|---|---|
| 1 | Local aggregate `bash tests/unit.sh` fails in 3 daemon-start-dependent files in this long-running workstation state; `daemon_test.sh`, `lock_test.sh`, and `log_reason_test.sh` pass individually. CI runs from a clean environment. |
| 2 | The skill is a protocol and routing capability; it does not install Maestro globally or add project-specific flows to `cashflow-guard`. |

---

## 🎯 Close Checklist / Priority Order

  ☑  1. 🧪  Focused role/skill/init/update/contract tests pass.
  ☑  2. 🐛  Audit-discovered test contract gap fixed: `commands_role_test.sh` now asserts `qa-automation-engineer`.
  ☑  3. 🔍  Stream audit anchored here.
  ☑  4. ⚡  No performance-sensitive runtime code changed.
  □  5. ✅  Commit, push, merge to `main`, and tag release after git verification.
