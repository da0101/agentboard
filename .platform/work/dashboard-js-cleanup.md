---
stream_id: stream-dashboard-js-cleanup
slug: dashboard-js-cleanup
type: refactor
status: planning
agent_owner: codex
domain_slugs: [vscode-extension]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/dashboard-js-cleanup
created_at: 2026-06-27
updated_at: 2026-06-27
closure_approved: false
---

# dashboard-js-cleanup

## Scope
- Refactor `extensions/vscode/media/dashboard.js`, currently flagged as a critical 1000+ line monolith.
- Preserve the webview runtime behavior and public dashboard messaging/API contracts.
- Split the file by responsibility into small modules with each resulting file targeted under 300 lines.
- Add focused tests for extracted behavior where the existing test harness can cover it.
- Out of scope: product behavior changes, visual redesign, command contract changes, stream closure, commit/push.

## Done criteria
- [ ] Phase 0 baseline recorded: tests, references, public exports, runtime-critical paths.
- [ ] Full audit completed and anchored in this stream file.
- [ ] Refactor plan approved by human before any production code changes.
- [ ] Extracted modules each have at least one happy-path and one edge/error-case test.
- [ ] Full relevant test suite run after every extraction and at final regression.
- [ ] Manual QA artifact created or not-required reason recorded.
- [ ] `.platform/memory/log.md` appended.
- [ ] `decisions.md` updated if any architectural choices were made.

## Key decisions
2026-06-27 — Treat `dashboard.js` as a behavior-preserving webview refactor — user explicitly requested a production-grade monolith split with Phase 2 approval before code changes.

## Worktree / Local environment

| Repo | Worktree path | Branch | Base | Dependencies | Local command | Localhost port(s) |
|---|---|---|---|---|---|---|
| repo-primary | `/Users/danilulmashev/Documents/GitHub/agentboard-dashboard-js-cleanup` | `feature/dashboard-js-cleanup` | `develop` | `npm ci --prefix extensions/vscode` installed | `npm --prefix extensions/vscode run compile`; dashboard webview is launched by VS Code extension host | n/a |

## Resume state
_Overwritten by `ab checkpoint` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** 2026-06-27 by danilulmashev
- **What just happened:** Phase 3 was approved; implementation worktree was created and extension dependencies installed.
- **Current focus:** Begin behavior-preserving module extraction from `extensions/vscode/media/dashboard.js`.
- **Next action:** Extract constants/utilities first, then run extension compile and focused tests.
- **Blockers:** none

## Progress log
_Append-only. `ab checkpoint` prepends a dated line and auto-trims to the last 10 entries. Format: `YYYY-MM-DD HH:MM — <what happened>`._

2026-06-27 14:28 — Re-ran Phase 0 baseline, re-read dashboard.js end to end, and prepared the refreshed Phase 2 extraction plan without production code changes.

2026-06-27 13:58 — Completed Phase 0 safety baseline, read all of dashboard.js, classified the monolith risks, and anchored the Phase 2 extraction plan without production code changes.

2026-06-27 00:00 — Stream registered for the `extensions/vscode/media/dashboard.js` production-grade cleanup.

## Open questions
_Things blocked on user input. Remove when resolved._

---

## Cleanup Plan / Audit Anchor

## Phase 0 Safety Net

- Baseline root suite: `bash tests/unit.sh --verbose` -> 476 passing / 2 failing / 0 skipped, 478 tests run, 2 of 60 files failed.
- Pre-existing root failures:
  - `tests/unit/file_size_ratchet_test.sh` -> `test_bash_files_respect_size_ratchet`: `lib/agentboard/commands/checkpoint.sh` is 509 lines, frozen at 475.
  - `tests/unit/session_track_test.sh` -> `test_file_poller_logs_changed_tracked_files`: temp fixture events log did not contain `package.json`.
- Extension baseline:
  - `npm --prefix extensions/vscode run compile` -> pass.
  - `node extensions/vscode/tests/linecount.test.js` -> 31 passing / 0 failing.
  - `node extensions/vscode/tests/dashboard-helpers.test.js` -> 34 passing / 0 failing.
  - `node extensions/vscode/tests/nickname-hash.test.js` -> 47 passing / 0 failing.
  - `node extensions/vscode/tests/parseEtime.test.js` -> 19 passing / 0 failing.
  - `node extensions/vscode/tests/workspace-root.test.js` -> 4 passing / 0 failing.
- References:
  - Runtime loader: `extensions/vscode/src/dashboard/shell.ts:13` loads `media/dashboard.js`.
  - Tests reference duplicated logic from `dashboard.js`: `extensions/vscode/tests/nickname-hash.test.js`, `extensions/vscode/tests/linecount.test.js`.
- Public export/API contract:
  - No ES module or CommonJS exports.
  - Implicit webview contract: `window._vscode`, persisted state keys (`_streamOpenState`, `_sectionFolded`, `_kpiFolded`, `_agentExpanded`, `_workflowExpanded`, `_actCollapsed`, `_catExpanded`, `_selectedRole`, `_rolesData`, `_ignoredSizeFiles`, `_stSession`, `_stSiblings`, `_wfAgentExpanded`), DOM ids/data attributes, and VS Code `postMessage` command names.
- Runtime-critical paths:
  - Startup script load via dashboard shell, initial `#ab-data` parse, `webviewReady` post, `message` update listener, change/click/keydown delegated event handlers, `applyUpdate` render pipeline.

## Phase 1 Audit

Function/responsibility map:

| Lines | Size | Responsibility |
|---|---:|---|
| 4-34 | 31 | VS Code API handle, UI state load/save helpers, constants, escaping/DOM helpers |
| 36-78 | 43 | Active stream card rendering |
| 80-87 | 8 | Session nickname vocabulary/hash |
| 88-135 | 48 | Small DOM utilities, tab switching, relative time, stream toggles, context bar, section fold state |
| 140-205 | 66 | Role and catalog column rendering |
| 207-314 | 108 | KPI computation and KPI HTML rendering |
| 316-351 | 36 | Session tab header rendering |
| 353-1111 | 759 | Main `applyUpdate` god function: session-tab normalization, header/now block, file activity, agent/workflow panels, multi-session cards, streams, stats, catalog, footer |
| 1113-1120 | 8 | Update event listener and webview ready handshake |
| 1122-1131 | 10 | Keydown and stream-select change handlers |
| 1134-1433 | 300 | Monolithic click delegation: KPI/section folds, navigation, refresh, file menu, workflow/activity/agent toggles, role/catalog actions, stream file opens |
| 1435-1443 | 9 | Initial embedded JSON bootstrap |

Classified violations:

- SRP: `applyUpdate` mixes data normalization, DOM querying, string-template rendering, state mutation, layout mode switching, and catalog/footer updates.
- SRP: click delegation handles unrelated commands, menu construction, persisted UI toggles, and navigation in one 300-line handler.
- DRY: file activity row and size/edit warning logic is duplicated in single-session and multi-session paths.
- DRY: model color/tag, live dot, context bar, pill/badge, and role/skill tag rendering are repeated inline.
- Coupling: render functions depend directly on `window.*`, DOM ids, CSS classes, `vscode.postMessage`, and persisted state shapes.
- Testability: pure formatting/threshold decisions are embedded in HTML builders and event handlers instead of exported pure helpers.
- Readability/complexity: nested branches inside `applyUpdate` exceed three levels around session cards, workflow agent state, and activity rendering.
- Magic values: freshness windows (120s/180s/5min/30s), thresholds (50/150/500/800/1000), menu dimensions, colors, labels, and command strings are inline.
- Side effects inside transform-like functions: render functions write `innerHTML`, mutate `window` state, and directly query DOM while also building strings.
- Potential bug surfaced: multi-session rendering builds `agentsHtml`, `workflowHtml`, `actHdr`, and `actBody`, but line 1039 returns only `hdr`; this appears to hide computed agent/workflow/activity content. Treat as audit finding, not a cleanup fix without approval.

## Phase 2 Proposed Extraction Plan

Target directory: `extensions/vscode/media/dashboard/`. Keep `extensions/vscode/media/dashboard.js` as the loaded thin orchestrator. Update `extensions/vscode/src/dashboard/shell.ts` to load module scripts in dependency order before the orchestrator. Each module attaches to one internal namespace, with CommonJS export only for tests.

| Extraction | Source lines | New file | Est. new lines | Est. final `dashboard.js` lines | Why safe | New tests |
|---|---:|---|---:|---:|---|---|
| Constants/utilities | 4-34, 88-103, threshold snippets from 516-528 and 980-994 | `extensions/vscode/media/dashboard/core.js` | 150 | 230 | No external importer; preserves `window._vscode`, escaping, command strings, thresholds, and formatting behavior under a namespace | Happy: `esc`, `relTime`, `ctxBar`, size/edit badges. Edge: invalid date/null pct/boundary thresholds |
| UI state | 6-29, 104-135, fold/toggle state writes from 1136-1163 and 1336-1422 | `extensions/vscode/media/dashboard/uiState.js` | 180 | 210 | Keeps same persisted `window._*` keys and calls `vscode.setState` through existing handle | Happy: save/restore sets. Edge: missing `getState`/bad state/no target element |
| Stream/catalog renderers | 36-78, 140-205, 1100-1106, role/card click rendering dependency | `extensions/vscode/media/dashboard/catalogRenderers.js` | 220 | 190 | Pure HTML output can be compared before/after; data attributes remain unchanged | Happy: stream list and role selection HTML. Edge: empty streams/items, long descriptions, selected role |
| KPI renderers | 207-314 | `extensions/vscode/media/dashboard/kpis.js` | 160 | 175 | Computation already pure except fold-state read; output can be snapshot-tested | Happy: multi-session aggregate. Edge: no sessions, high context, code-health thresholds |
| Session identity | 80-87, 316-351, model/nickname snippets from 704-759 | `extensions/vscode/media/dashboard/sessionIdentity.js` | 170 | 160 | Preserves nickname arrays/hash and header data attributes; nickname parity tests already exist | Happy: nickname/header render. Edge: missing model/session id/siblings |
| Activity rows/menu model | 497-560, 970-1028, 1192-1294 | `extensions/vscode/media/dashboard/activityMenu.js` | 260 | 140 | Removes duplicated row logic while preserving `data-open-diff`, menu commands, and thresholds | Happy: edited file row and refactor menu. Edge: new/deleted files, large file threshold, provider-specific menu item |
| Agent/workflow renderers | 562-669, 762-968, 1296-1391 | `extensions/vscode/media/dashboard/agentWorkflowRenderers.js` | 270 | 130 | Moves HTML builders and toggle helpers without changing `window._agentExpanded`, `_workflowExpanded`, `_actCollapsed`, `_wfAgentExpanded` | Happy: running/done workflow agents. Edge: transcript fallback, standby count, background workflow |
| Main update orchestrator | Remaining control flow from 353-1111 after renderer extraction | `extensions/vscode/media/dashboard/updateOrchestrator.js` | 260 | 120 | Keeps `applyUpdate` behavior but delegates rendering; same DOM ids, same update payload contract | Happy: main hub update. Edge: session tab payload, no sessions, catalog counts |
| Event wiring/bootstrap | 1113-1443 after menu/toggle extraction | `extensions/vscode/media/dashboard/events.js` | 240 | 90 | Same delegated selectors and `vscode.postMessage` commands; `dashboard.js` only wires startup | Happy: click/change posts expected command. Edge: Escape hides menu, missing menu/target |

Murphy check:

- Most fragile thing: preserving the implicit global/browser contract while splitting a non-module webview script. The code depends on load order, global functions/state, DOM ids, and exact `postMessage` command payloads rather than typed imports.
- Guard: first add characterization tests around the namespace modules and command payload builders, load scripts in explicit order from `shell.ts`, keep `dashboard.js` as a compatibility orchestrator, run extension compile/tests after each extraction, and manually verify the dashboard webview after Phase 4.

Approval gate:

- Stop here until the human approves Phase 3 implementation.
