---
stream_id: stream-code-cleanup-skill-role
slug: code-cleanup-skill-role
type: feature
status: awaiting-verification
agent_owner: codex
domain_slugs: [agent-roles-skills]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/code-cleanup-skill-role
created_at: 2026-06-13
updated_at: 2026-06-13
closure_approved: false
---

# code-cleanup-skill-role

## Scope
- Add a reusable cleanup skill that agents use when asked to clean up a whole codebase, a feature, a function, a file, or a folder.
- Add or update a role profile so cleanup requests route to the right senior-agent identity before the skill runs.
- Define a safe cleanup workflow: scan first, classify findings, propose changes, preserve behavior, test, and report evidence.
- Cover targets such as duplicated logic, dead code, oversized files, excessive comments, avoidable complexity, performance hotspots, housekeeping, and maintainability.
- Out of scope until explicitly approved: executing broad cleanup changes without an approved plan, rewriting unrelated architecture, or committing/pushing.

## Done criteria
- [x] Research-backed plan approved by the user before implementation.
- [x] Isolated worktree exists for `feature/code-cleanup-skill-role`, with dependencies and local commands recorded.
- [x] Cleanup skill is added to shipped templates and installed local skill dirs needed for current providers.
- [x] Cleanup role is added or existing role routing is updated, with README/CHEATSHEET/docs updated where user-facing.
- [x] Tests cover skill/role pack integrity and any changed install/update behavior.
- [x] Manual QA or command-level verification confirms a fresh project can discover the role and skill.
- [x] `.platform/memory/log.md` appended.
- [x] `decisions.md` updated if any architectural choices were made.

## Key decisions
_Append-only. Format: `YYYY-MM-DD — <decision> — <rationale>`_

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/Users/danilulmashev/Documents/GitHub/agentboard-code-cleanup-skill-role` | `feature/code-cleanup-skill-role` | `develop` | no install needed; bash CLI with shell tests | `bash tests/unit/roles_pack_test.sh` / focused `bash tests/unit/*_test.sh` | none; CLI project |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-13 — by codex
- **What just happened:** Implemented and verified `ab-cleanup`, `code-cleanup-engineer`, provider/template routing, main-side Graphify carry-forward, and Graphify cache ignore coverage.
- **Current focus:** Awaiting user verification/review.
- **Next action:** User reviews changes; if accepted, ask explicitly before committing. Do not close/archive until user approves stream closure.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-13 00:00 — Registered stream and domain for cleanup skill/role feature.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## 🔍 Audit — 2026-06-14

> Run via Stream / Feature Analysis Protocol — 1 read-only repo audit.

# 📋 code-cleanup-skill-role — Audit Snapshot

> **Stream:** `code-cleanup-skill-role` · **Date:** 2026-06-14 · **Status:** 🟢 awaiting-verification
> **Repos touched:** repo-primary (`agentboard`)

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ agentboard |
|---|:---:|
| **Implementation** | 🟢 |
| **Tests**          | 🟢 |
| **Security**       | 🟢 |
| **Code Quality**   | 🟢 |

> **Bottom line:** Cleanup role/skill is present in shipped templates and provider runtime copies, with Graphify/cache contracts covered and no blocking findings.

---

## 🔄 How the Feature Works (End-to-End)

```
User asks to clean up repo/path/file/function
  -> .platform/roles/INDEX.md routes to code-cleanup-engineer
  -> ab-cleanup scans target before editing
  -> agent ranks findings, batches safe behavior-preserving work
  -> tests/lints/manual QA verify preservation before report
```

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🟢 Clean | agentboard | Cleanup stream is protocol/template content only; no secrets, auth/data paths, new dependencies, or executable command behavior added. Behavior-preservation and approval rules are explicit at `templates/skills/ab-cleanup/SKILL.md:20` and `templates/skills/ab-cleanup/SKILL.md:94`. |

---

## 🧪 Test Coverage

### agentboard
| Area | Tested? | File |
|---|:---:|---|
| Cleanup skill/role Graphify contract | ✅ Strong | tests/unit/cleanup_graphify_contract_test.sh:10 |
| Fresh init installs cleanup skill copies | ✅ Strong | tests/unit/cleanup_graphify_contract_test.sh:46 |
| Runtime cache ignore | ✅ Strong | tests/unit/commands_init_test.sh:20 |
| Update restores runtime gitignore block | ✅ Strong | tests/unit/commands_update_test.sh:73 |
| Role pack integrity | ✅ Strong | tests/unit/roles_pack_test.sh:14 |

---

## ✅ Implementation Status

### agentboard
| Component | Status | Location |
|---|:---:|---|
| `ab-cleanup` shipped skill | ✅ Done | templates/skills/ab-cleanup/SKILL.md:1 |
| Provider installed skill copies | ✅ Done | .claude/skills/ab-cleanup/SKILL.md:1 / .agents/skills/ab-cleanup/SKILL.md:1 |
| `code-cleanup-engineer` role | ✅ Done | templates/platform/roles/code-cleanup-engineer.md:1 |
| Role routing | ✅ Done | templates/platform/roles/INDEX.md:46 |
| Cleanup scan/safety workflow | ✅ Done | templates/skills/ab-cleanup/SKILL.md:37 |
| Graphify JSON contract | ✅ Done | templates/skills/ab-cleanup/SKILL.md:66 |
| Graphify cache ignored | ✅ Done | .gitignore:36 |
| Durable decision | ✅ Done | .platform/memory/decisions.md:46 |

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
| 1 | Cleanup skill defines the workflow and routing; it does not run a cleanup by itself until a future user request targets a repo/path. |
| 2 | Stream remains in `awaiting-verification`; closure/archive still requires explicit owner sign-off and `closure_approved: true`. |

---

## 🎯 Close Checklist / Priority Order

  ☑  1. 🧪  Cleanup Graphify/role/install contracts pass.
  ☑  2. 🐛  No blocking correctness issues found.
  ☑  3. 🔍  Stream audit anchored here.
  ☑  4. ⚡  No runtime performance code changed.
  □  5. ✅  Keep stream active until owner explicitly approves closure.
