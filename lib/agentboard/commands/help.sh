cmd_version() { say "ab $VERSION"; }

cmd_help() {
  cat <<'EOF'
ab — shared work-state for multi-provider AI workflows

Scaffolds a .platform/ pack plus provider-neutral entry files (CLAUDE.md,
AGENTS.md, GEMINI.md) so Claude Code, Codex CLI, and Gemini CLI each load
the same project truth and can resume the same workstreams across sessions.
Agentboard does NOT move chat history between providers — it shares files,
not conversations.

USAGE
  ab <command> [args]

COMMANDS
  install [--dir ...]        Install ab onto your PATH via a symlink
  init                       Scaffold a .platform/ pack in the current directory.
                             After init, open the project in an AI CLI and say
                             "activate this project" — the LLM scans your code
                             and fills in the context pack based on what it finds.

  update [--dry-run]         Update process files to the latest ab version.
                             Replaces: workflow.md, ONBOARDING.md, ACTIVATE.md,
                               conventions/*.md, domains/TEMPLATE.md,
                               scripts/sync-context.sh
                             Adds if missing: learnings.md, BACKLOG.md
                             Never touches: architecture.md, decisions.md, log.md,
                               STATUS*.md, repos.md, work/*, domains/*
                               except domains/TEMPLATE.md

  sync [--apply|--list]      Sync AGENTS.md + GEMINI.md from CLAUDE.md (default: check)
  bootstrap [--apply-domains] Discover repos, infer starter domains, and suggest streams
  migrate [--apply]          Upgrade legacy stream/domain files to metadata v1
  migrate-layout [--apply]   Upgrade .platform/ layout — move decisions/learnings/
                             log/gotchas/playbook/open-questions/BACKLOG into
                             .platform/memory/. Cleans up empty sessions/.
                             Default is --dry-run; pass --apply to perform.
  brief-upgrade [slug] ...   Rewrite legacy BRIEF.md for one target stream
  doctor                     Validate active .platform state and metadata
  new-domain <slug> ...      Create a domain file from the shared template
  new-stream <slug> ...      Create a stream file and register it in work/ACTIVE.md
                             --domain <slug>  (repeatable, required)
                             --base-branch <b> branch to fork from (prompts if omitted)
                             --branch <name>  git branch name for this stream
                             --type <t>       stream type (default: feature)
                             --agent <a>      agent owner (default: codex)
                             --repo <id>      (repeatable)
  resolve <target>           Resolve a stream, domain, or repo by canonical id
  current-stream             Resolve the canonical current stream slug
                             --stream <slug>   explicit slug override
                             --session-id <id> use or remember session mapping
                             --remember        persist session-id -> stream
                             --quiet           print only the slug
  next-action [slug]         Print the canonical next action for a stream
                             --session-id <id> resolve stream from session
                             --quiet           print only the action text
  handoff [stream-slug]      Print a low-token provider handoff packet.
                             Shows Resume state (from stream file), warns if
                             stale, appends a "for the agent reading this"
                             footer. Flags:
                             --budget <N|Nk>   cap estimated load-order tokens;
                                               drops secondary domains when tight
  checkpoint <stream-slug>   Save compact "where we are" state before handoff.
                             Overwrites the stream's ## Resume state block,
                             prepends a Progress log entry, trims to last 10.
                             Run this before ending a session or switching CLIs.
                             --what "<text>"   required: what just happened
                             --next "<text>"   required: the single next action
                             --blocker "<t>"   current blocker (default: none)
                             --focus "<t>"     file:line or topic in focus
                             --diff            also append git diff --stat
                             --dry-run         print changes without writing
                             --tokens-in N --tokens-out N --provider <p>
                             [--model <m>] [--type <t>] [--complexity <c>]
                                               auto-log a usage segment
  checkpoint --auto [slug]   Auto-checkpoint the single active stream using the
                             latest git commit as --what. Called by the
                             post-commit hook after every commit (all providers).
                             Fails silently if ambiguous or not in a git repo.
  recover <stream-slug>      Reconstruct a checkpoint from git log when context
                             was lost without a manual checkpoint. Scans
                             commits since the stream's last updated_at.
                             --confirm         write the recovery checkpoint
                             --since <ref>     override the scan range
  events <sub>               Cross-provider tool-call event log (JSONL).
                             Captured automatically by Claude Code hooks;
                             Codex/Gemini can pipe into .platform/scripts/
                             hooks/event-logger.sh from their own hooks.
                             tail [-n N]       last N events
                             since <ISO-ts>    events at or after timestamp
                             stream <slug>     events tagged with stream
                             stats             event count + top tools
                             clear [--confirm] archive the log
                             path              print log file path
                             --json            raw JSONL output
  close <stream-slug>        Finalize a stream. Two-step ritual:
                             1. bare run prints the harvest checklist —
                                distill gotchas/playbook/questions/decisions
                                into .platform memory files.
                             2. --confirm archives the stream and logs closure.
                             --dry-run         preview --confirm actions
  brief                      Print the compact project briefing — active
                             streams, recent gotchas, open questions,
                             usage pattern. Read this at session start.
                             --all             show all gotchas/questions
  watch                      Background poller that auto-checkpoints when
                             ≥1 tracked file has changed since last poll.
                             Use during long Codex/Gemini sessions so state
                             stays current without manual checkpoints.
                             --interval N      poll every N min (default 10)
                             --threshold N     min changed files (default 1)
                             --stream <slug>   target stream (default: auto)
                             --once            single poll, then exit
                             --stop            stop the running watcher
                             --install         install per-project scheduler
                             --uninstall       remove per-project scheduler
                             --status          report scheduler state + log path
                             AGENTBOARD_WATCH_HOME=<dir>  isolate scheduler
                                               files for tests / dry local runs
  install-hooks              Install Claude Code hook guards. Wires a
                             PreToolUse hook that blocks git commit / push /
                             reset --hard / rm -rf with an approval prompt.
                             LLM cannot bypass. Safe on re-install.
                             --force           overwrite existing settings.json
                             --dry-run         preview without writing
  progress <stream-slug>     Append a git-diff summary to the stream's
                             ## Progress log section (uses base_branch from
                             frontmatter). Flags:
                             --base <branch>   override recorded base branch
                             --note "<text>"   one-line note to attach
                             --dry-run         print block instead of writing
  search <query terms...>    Search .platform/ context files for relevant
                             snippets. Each term is OR-matched (case-insensitive).
                             Shows file path + surrounding context + full-file
                             token estimate. Use before loading full files.
                             -C N, --context N   context lines (default 3)
                             -q, --quiet         file paths only
                             --domains           domains/ only
                             --memory            memory/ only
                             --conventions       conventions/ only
  status                     Print .platform/STATUS.md to stdout
  add-repo <path>            Copy per-repo entry file templates to a new repo
                             Refuses to overwrite existing entry files.
  usage [subcommand]         Track token consumption across all projects (SQLite).
                             summary       — totals by provider/model/repo/type
                             log           — record a context segment
                               --provider <name> --input <N> --output <N>
                               [--model <M>] [--stream <S>] [--repo <R>]
                               [--type <T>] [--complexity <C>] [--note <text>]
                             stream <slug> — full breakdown for one stream
                             history       — last 20 segments
                             optimize      — most expensive streams/types/providers
                             learn         — detect inefficiencies and generate rules
                             learn --apply — write rules to .platform/memory/learnings.md
                             dashboard     — visual bar-chart dashboard
                               [--today|--week|--month]
                             One entry = one context segment. Log at every
                             context clear, provider switch, or stream closure.
  version                    Print version
  help                       Show this help

PHILOSOPHY
  No stack pre-picking. No assumptions. The LLM decides what conventions to
  write based on your actual codebase during activation.
EOF
}
