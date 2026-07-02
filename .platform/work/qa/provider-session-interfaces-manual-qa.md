## Manual QA Artifact

Scope: Provider-specific session interfaces in the Agentboard VS Code dashboard,
with emphasis on Claude/Codex visual treatment and safe stale Codex cleanup.

Environment: Local VS Code extension host from branch
`feature/provider-session-interfaces` in
`/private/tmp/agentboard-provider-session-interfaces`. Build with
`cd extensions/vscode && npm run compile`, then launch/reload the extension host.
No localhost server is expected.

Test data:
- One workspace with `.platform/work/ACTIVE.md`.
- At least one Claude session snapshot and one Codex session snapshot under
  `.platform/runtime/agentboard/sessions/`.
- For stale cleanup, create or wait for a Codex snapshot with `ageSeconds >= 180`
  or `_last_updated` older than 3 minutes but still recent enough to render.

Safety limits:
- Do not run `agentboard close <stream>` during this QA unless separately
  approved.
- Do not terminate live Claude/Codex terminal processes from this flow.
- The session clear action should only remove the dashboard runtime session JSON.

Happy path:
1. Open VS Code on the worktree and run `Agentboard: Open Dashboard` -> Expected:
   the Live dashboard opens without script or CSP errors.
2. With a Claude session visible -> Expected: the session card/header shows a
   `Claude` provider badge with orange accent styling.
3. With a Codex session visible -> Expected: the session card/header shows a
   `Codex` provider badge with blue accent styling.
4. With exactly one Claude or Codex session visible -> Expected: the NOW banner
   and single `Session` stats section use the provider label/accent with a flat,
   transparent tint; no Claude/Codex gradient backgrounds should appear.
5. In the main dashboard session list -> Expected: session cards show identity,
   stream, branch, chat/tab controls, agents, and workflow only; no embedded
   Activity feed appears inside the card.
6. With new or deleted files in `git status` -> Expected: the trend chart legend
   and hover tooltip include `New` and `Deleted` KPI series when those counts are
   non-zero.
7. Open a Codex session tab -> Expected: the header keeps the Codex badge/accent,
   shows `Open Chat`, and shows a safe cleanup button.
8. Inspect a Codex session with no attributed workers -> Expected: worker section
   reads `Workers` and the empty state says `No Codex workers attributed yet`.
9. Inspect a Claude session with no attributed sub-agents -> Expected: section
   reads `Sub-agents` and the empty state remains Claude-specific.

Bug repro / regression:
1. Create a stale Codex snapshot in `.platform/runtime/agentboard/sessions/`.
2. Refresh the dashboard -> Expected: the stale Codex card action reads
   `Clear stale Codex`.
3. Click `Clear stale Codex` -> Expected: the session disappears after refresh,
   the corresponding session JSON is removed, and no source files or terminal
   processes are deleted or terminated.

Edge cases:
- Unknown provider session -> Expected: renders as neutral `Agent` without
  throwing.
- Gemini provider session, if present -> Expected: renders with the Gemini badge
  and distinct accent; no full Gemini-specific behavior is required.
- Multiple sessions mixed across Claude/Codex -> Expected: each card keeps its
  own provider accent and actions; no global theme bleed or gradient treatment.
- Live Codex session -> Expected: close action says `Dismiss`, not
  `Clear stale Codex`.
- Repo with recent Claude events but no session snapshot -> Expected: dashboard
  still shows one repo-scoped Claude session derived from `.platform/events.jsonl`.
- Claude modifies files through a meaningful Bash command -> Expected: the hook
  emits session-scoped `FileChange` rows for dirty repo files so the Claude
  activity list includes those changed files, not only direct Edit/Write tools.
- Claude activity row points at an absolute path in a sibling worktree ->
  Expected: the dashboard resolves that file's git root and shows changed-line
  stats / line-count badges when the file has a diff.
- Claude hook payload with `transcript_path` but no `session_id` -> Expected:
  the hook writes a repo-local Claude session snapshot using a stable derived id,
  and it must not reuse a Codex `AGENTBOARD_SESSION_ID` from the environment.
- Session clear from a different repo root -> Expected: extension refuses the
  action and leaves the other repo's session snapshot intact.

Browser/device checks: VS Code webview desktop only. Check narrow sidebar width
and full panel width; provider badges and cleanup buttons must not overlap model,
chat, or tab controls.

Accessibility checks:
- Provider and cleanup buttons must have useful `title` tooltips.
- Color is not the only indicator: provider badges include text labels.
- Keyboard focus should still reach chat, tab, cleanup, refresh, and stream
  controls in DOM order.

Evidence to capture:
- Screenshot of mixed Claude/Codex session cards.
- Screenshot of stale Codex `Clear stale Codex` action.
- Before/after file list showing only the stale session JSON was removed.

Automation notes:
- Stable message command for cleanup remains `closeSession`.
- This QA does not require Playwright unless a VS Code webview automation harness
  is available.

Signoff: pending human VS Code dashboard verification.
