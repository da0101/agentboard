cmd_version() { say "agentboard $VERSION"; }

cmd_help() {
  cat <<'EOF'
agentboard — AI agent context kit

Bootstraps a .platform/ context pack into any project so that Claude Code,
Codex CLI, and Gemini CLI are instantly productive.

USAGE
  agentboard <command> [args]

COMMANDS
  install [--dir ...]        Install agentboard onto your PATH via a symlink
  init                       Scaffold a .platform/ pack in the current directory.
                             After init, open the project in an AI CLI and say
                             "activate this project" — the LLM scans your code
                             and fills in the context pack based on what it finds.

  update [--dry-run]         Update process files to the latest agentboard version.
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
  brief-upgrade [slug] ...   Rewrite legacy BRIEF.md for one target stream
  doctor                     Validate active .platform state and metadata
  new-domain <slug> ...      Create a domain file from the shared template
  new-stream <slug> ...      Create a stream file and register it in work/ACTIVE.md
  resolve <target>           Resolve a stream, domain, or repo by canonical id
  handoff [stream-slug]      Print a low-token provider handoff packet
  claim "<task>"             Add a row to .platform/sessions/ACTIVE.md
  release                    Remove your rows from .platform/sessions/ACTIVE.md
  log "<one line>"           Append a timestamped line to .platform/log.md
  status                     Print .platform/STATUS.md to stdout
  add-repo <path>            Copy per-repo entry file templates to a new repo
                             Refuses to overwrite existing entry files.
  usage [subcommand]         Track token consumption across all projects (SQLite).
                             Subcommands: summary (default) | log | history | optimize
                             Log: --provider <name> --input <N> --output <N>
                               [--model <M>] [--stream <S>] [--repo <R>] [--type <T>]
  version                    Print version
  help                       Show this help

ENV
  AGENTBOARD_AGENT           Agent name used in claim/release (default: $USER@$HOSTNAME)

PHILOSOPHY
  No stack pre-picking. No assumptions. The LLM decides what conventions to
  write based on your actual codebase during activation.
EOF
}

