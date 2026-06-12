---
stream_id: stream-search-command
slug: search-command
type: feature
status: in-progress
agent_owner: claude-code
domain_slugs: [commands]
repo_ids: [repo-primary]
base_branch: develop
git_branch: feature/search-command
created_at: 2026-04-19
updated_at: 2026-04-19
closure_approved: false
---

# search-command

## Scope

- Add `agentboard search <query>` CLI command — searches `.platform/` context files
- OR-join query terms (case-insensitive), ripgrep/grep fallback, context lines, scope flags
- Register in `bin/agentboard` dispatcher + add to help catalog
- Add one-line instruction to all three root entry templates (CLAUDE.md, AGENTS.md, GEMINI.md)
- OUT OF SCOPE: MCP server, vector embeddings, semantic ranking

## Done criteria

- [ ] `lib/agentboard/commands/search.sh` created with `cmd_search` + `_search_help`
- [ ] `bin/agentboard` sources `search.sh` and routes `search)` case
- [ ] `help.sh` catalog updated with `search` entry
- [ ] All three root templates updated with "Finding relevant context" instruction
- [ ] `agentboard search "some term"` works end-to-end in agentboard's own .platform/
- [ ] `.platform/memory/log.md` appended

## Key decisions

2026-04-19 — OR-join query words into a single regex pattern — simpler than multi-pass intersection; BM25-style behavior without external deps
2026-04-19 — prefer rg over grep but never require it — matches agentboard "no required deps" rule
2026-04-19 — instruction in templates is "before loading full files, run search first" — instruction-driven, works for all three LLMs identically

## Resume state

- **Last updated:** 2026-04-19 — by claude-code
- **What just happened:** search.sh created, bin/agentboard updated, help.sh updated, all three templates updated
- **Current focus:** verification
- **Next action:** smoke test `agentboard search` against .platform/ files, then close stream
- **Blockers:** none

## Progress log

2026-04-19 14:00 — Implementation complete: search.sh + dispatcher + help + templates
