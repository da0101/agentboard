# Agentboard Cheat Sheet

Shared work-state and project-truth across Claude Code, Codex CLI, and Gemini
CLI. Agentboard shares files, not chat history — each CLI loads the same
`.platform/` pack on its own.

## Setup

```bash
agentboard install                   # symlink to ~/bin (adds to PATH)
agentboard init                      # scaffold .platform/ into current project
```

---

## Project lifecycle

```bash
agentboard update [--dry-run]        # pull in newer shipped files (keeps project truth)
agentboard sync [--apply|--list]     # sync AGENTS.md / GEMINI.md from CLAUDE.md
agentboard bootstrap [--apply-domains]  # discover repos, suggest domains & streams
agentboard migrate [--apply]         # upgrade legacy stream/domain files to v1 metadata
agentboard brief-upgrade <slug> [--apply]  # rewrite legacy BRIEF.md to single-stream format
agentboard doctor                    # validate .platform/ state, metadata, domain refs
agentboard status                    # print .platform/STATUS.md
agentboard version
agentboard help
```

---

## Domains & Streams

```bash
# Create a domain
agentboard new-domain <slug> [--repo <id>]

# Create a stream
agentboard new-stream <slug> \
  --domain <domain-slug> \
  [--type feature|bug|audit|chore] \
  [--agent codex|claude|gemini] \
  [--repo <id>] \
  [--base-branch develop] \
  [--branch feature/<slug>]

# Inspect
agentboard resolve <stream-slug|domain-slug|repo-id>
agentboard handoff [stream-slug] [--budget <N|Nk>]
                                     # load order + Resume state + branch hint.
                                     # Warns if state is stale; footer tells the
                                     # next agent what to do. --budget drops
                                     # secondary domains when tokens run tight.
agentboard checkpoint <slug> --what "..." --next "..." [--blocker "..."] [--focus "..."] [--diff]
                                     # save compact "where we are" before handoff.
                                     # Overwrites stream's ## Resume state block,
                                     # prepends Progress log entry, trims to last 10.
                                     # Run before ending session or switching CLI.
agentboard progress <slug> [--base <b>] [--note "<text>"] [--dry-run]
                                     # append git diff --stat to stream's Progress log
```

---

## Token usage tracking

### Log a segment (run before every context clear or provider switch)

```bash
agentboard usage log \
  --provider claude \
  --model claude-sonnet-4-6 \
  --input 45000 --output 8000 \
  --stream <stream-slug> \
  --type implementation \
  --repo <repo-name> \
  --note "segment 2 — added webhook handler"
```

`--provider` `claude` | `codex` | `gemini`
`--type`     `research` | `implementation` | `debug` | `audit` | `hardening` | `chore`
`--repo`     auto-detected from cwd if omitted
`--note`     optional but recommended

### View & analyse

```bash
agentboard usage summary             # global 30-day totals by provider/model/repo/type
agentboard usage history             # last 20 raw entries
agentboard usage stream <slug>       # all segments for one stream + per-provider totals
agentboard usage dashboard           # visual bar charts (all time)
agentboard usage dashboard --today   # today only
agentboard usage dashboard --week    # last 7 days
agentboard usage dashboard --month   # last 30 days
agentboard usage optimize            # most expensive task types and streams
agentboard usage learn               # detect patterns (MODEL_OVERKILL, RESEARCH_BLOAT …)
agentboard usage learn --apply       # write findings to .platform/learnings.md
```

### Direct SQLite queries

```bash
sqlite3 ~/.agentboard/usage.db "
  SELECT stream_slug, SUM(total_tokens) AS total, COUNT(*) AS segments
  FROM usage GROUP BY stream_slug ORDER BY total DESC LIMIT 10;"
```

---

## Multi-repo hub

```bash
agentboard add-repo <path>           # scaffold thin entry files into a sibling repo
```

---

## Token estimation guide

| Session weight | Input estimate | Output estimate |
|---|---|---|
| Light (few reads, short answers) | 10k–25k | 2k–5k |
| Medium (several files, some code) | 25k–60k | 5k–15k |
| Heavy (many files, long impl) | 60k–120k | 15k–40k |
| Context nearly full | 150k–200k | 20k–50k |

Output is typically 10–30% of input. Lean toward over-estimating input.

---

## Usage DB location

```
~/.agentboard/usage.db
```
