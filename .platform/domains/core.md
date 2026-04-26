---
domain_id: dom-core
slug: core
status: active
repo_ids: [repo-primary]
related_domain_slugs: [commands]
created_at: 2026-04-17
updated_at: 2026-04-17
---

# core

## What this domain does

Shared helpers every command uses: color output, frontmatter parsing, path resolution, stream enumeration, domain/repo lookup. Nothing in here writes user-facing state directly — commands do that; core provides the primitives.

## Source of truth

All helpers live under `lib/agentboard/core/` and are sourced once at CLI load via `lib/agentboard/core.sh`. No command should duplicate these.

## Key files

- `lib/agentboard/core.sh` — orchestrator that sources the rest
- `lib/agentboard/core/base.sh` — color codes, `say` / `ok` / `warn` / `die`, frontmatter_value, has_frontmatter, replace_frontmatter_line, today, substitute
- `lib/agentboard/core/project_state.sh` — stream_files, domain_files, stream_resume_field, markdown_section_* helpers, stream_next_action
- `lib/agentboard/core/project_detection.sh` — detect hub mode, detect primary repo stack
- `lib/agentboard/core/bootstrap_repos.sh` — sibling-repo discovery for hub mode
- `lib/agentboard/core/bootstrap_domains.sh` — infer starter domains from repo layout

## API contract

Functions commands depend on — these signatures are locked:

```bash
frontmatter_value <file> <key>              # prints value; empty if missing
has_frontmatter <file>                       # return 0 if file starts with ---
replace_frontmatter_line <file> <key> <val>  # in-place update
stream_files                                 # yields .platform/work/*.md (excludes TEMPLATE/ACTIVE/BRIEF)
stream_resume_field <file> <label>           # parses - **<Label>:** <value> from ## Resume state
today                                        # YYYY-MM-DD
```

## Decisions locked

- Color output must be TTY-aware and respect `NO_COLOR=1`. Every test sets `export NO_COLOR=1` at the top.
- `frontmatter_value` is awk-only (no yq dep). Values are parsed as plain strings — no YAML type coercion.
- Core helpers must be pure functions of their inputs. No side effects to global state beyond color variables (set once at init).
- Core files are allowed to exceed the 300-line rule IF splitting would require duplicating helpers across files. `base.sh` / `project_state.sh` are the current exceptions.
