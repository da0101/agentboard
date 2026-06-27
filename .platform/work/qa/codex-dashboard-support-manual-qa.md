## Manual QA Artifact

Scope: Codex dashboard/session integration in the Agentboard VS Code extension.

Environment: local checkout on `feature/codex-dashboard-support`; VS Code desktop; Agentboard extension built from `extensions/vscode`; Codex CLI with project `.codex/config.toml` trusted or shell alias routed through `.platform/scripts/codex-ab`.

Test data: this repo or a small Agentboard-initialized fixture repo with one active stream and at least one tracked source file.

Safety limits: do not commit, push, delete branches, or run destructive shell commands during QA. Use a disposable test file for edits and revert it after verification.

Happy path:

1. From the feature worktree, run `cd extensions/vscode && npm run compile`.
   Expected: TypeScript compile succeeds.
2. Package without writing a tracked VSIX: `npx @vscode/vsce package --out /tmp/agentboard-codex-dashboard-support.vsix`.
   Expected: VSIX is created under `/tmp`, not in the repo.
3. Install: `code --install-extension /tmp/agentboard-codex-dashboard-support.vsix --force`, then reload VS Code.
   Expected: Agentboard extension reloads without activation errors.
4. Open the Agentboard repo in VS Code and run **Agentboard: Open Dashboard**.
   Expected: dashboard project label is `agentboard`; no stale global project hijack.
5. Start Codex via the wrapper alias or directly through `.platform/scripts/codex-ab`.
   Expected: `~/.agentboard/sessions/<codex-session>.json` appears with `_root` pointing at the current repo and `provider: codex`.
6. In that Codex session, edit a tracked disposable file.
   Expected: `.platform/events.jsonl` gets a Codex event with `hook_event_name: FileChange`, `tool: Edit`, `file_path`, and `file`.
7. Refresh/open the Agentboard dashboard Live tab.
   Expected: a Codex session column appears with model/runtime/branch; activity shows the edited file and line diff stats.
8. Launch a Codex subagent if available.
   Expected: Agentboard logs `AgentStart`/`AgentDone` with `provider: codex`; dashboard sub-agent list updates.
9. End the Codex session and wait at least one refresh cycle.
   Expected: session remains visible until idle threshold, then disappears or marks stale according to existing dashboard behavior.

Bug repro / regression:

1. Before this change, run Codex wrapper and edit a tracked file.
   Expected old behavior: no Codex session column because no `~/.agentboard/sessions/*.json`; file activity may be missing because only `file_path` was present.
2. After this change, repeat the same flow.
   Expected fixed behavior: session column exists and file activity is visible.

Edge cases:

- Codex native hooks not trusted: wrapper still writes session snapshots and file-poller events.
- Codex native hooks trusted: `codex-hook-bridge.js` writes direct tool/subagent events.
- Cost/context not present in Codex payload: dashboard leaves those fields blank/zero without crashing.
- Multiple active streams: event logger uses session mapping or explicit `AGENTBOARD_STREAM`; no cross-session contamination.
- `.agents/skills/<skill>/SKILL.md` read: event logger records a `Skill` event.

Browser/device checks: VS Code desktop on macOS; no browser viewport checks required.

Accessibility checks: verify dashboard remains keyboard-scrollable and existing buttons retain visible labels/tooltips; no UI layout changes were made.

Evidence to capture: screenshot of Codex session column, sample redacted session JSON, sample event JSONL line, terminal output for compile/tests.

Maestro / automation notes: not applicable; this is VS Code desktop/manual verification.

Signoff: pending human QA, 2026-06-26, BLOCKED until a live Codex session is run through the checklist.
