## Agentboard

Shared work-state for Claude Code, Codex and Gemini. Long procedures are on demand — `ab protocol` lists them, `ab protocol <name>` prints one.

**Session start:** run `ab brief --start`. One open stream → resume it (`ab handoff <slug>`); several → ask which; none → ask what to work on.

**Loading:** open only files named in `work/BRIEF.md` § "Relevant context". For a feature or topic run `ab recall <topic> [--layer backend|web|mobile]` before opening a domain file. Never read `work/archive/*`.

**No `ab` command on this machine?** Skip every `ab …` step: read `.platform/CARDS.md`, open only the one card that matches your task, and leave `work/archive/*` alone.

**Hard rules**
1. Task not in `work/ACTIVE.md`? Run `ab protocol new-task` before any research or code. New stream: research first, present the plan, wait for human approval.
2. Work on a `feature/<slug>` or `bugfix/<slug>` branch in the main checkout (`hotfix/<slug>` only if told). Worktrees are on demand: `ab worktree new <slug>`.
3. Only the human closes a stream (`ab protocol closure`). Record durable facts in the stream's `## Knowledge delta` as you work.
4. Change needs human or app-driving verification? `ab protocol qa` before any commit, push, merge or release.
5. Ending, low on context, or switching provider: `ab checkpoint <slug> --what "…" --next "…"` (`ab protocol handoff`).
6. After an edit another agent must understand: `ab log-reason "<why>"` (`ab protocol reasoning`).
7. **Role activation:** on the first task message match its intent to a role in `.platform/roles/INDEX.md` and adopt it; no confident match → `pair-programmer`, silently (`ab protocol roles`).
8. Audit or analysis of a stream: `ab protocol audit`.
9. User says "update the platform", "rescan" or "you're out of date": run `ab rescan`, then follow `.platform/RESCAN.md`.

**Silicon Valley product mindset:** act like best-in-class Silicon Valley product teams — user-obsessed, craft-driven, fast, rigorous — never as permission for scope creep, weak tests or skipping approval gates (`.platform/workflow.md`).
