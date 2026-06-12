---
stream_id: stream-platform-quality-fixes
slug: platform-quality-fixes
type: bugfix
status: done
agent_owner: claude-code
domain_slugs: [core]
repo_ids: [repo-primary]
base_branch: main
git_branch: main
created_at: 2026-04-18
updated_at: 2026-04-18
closure_approved: true
---

# platform-quality-fixes

## Scope
- Fix post-commit hook writing entries to bottom of log.md (should be newest-at-top)
- Add `agentboard doctor` activation quality checks (unfilled `{{PLACEHOLDER}}` in architecture.md, empty conventions/)
- Out of scope: other doctor checks, test suite changes, new features

## Done criteria
- [x] post-commit hook prepends after `---` separator instead of appending with `>>`
- [x] `agentboard doctor` warns when `architecture.md` has `{{` placeholders after activation
- [x] `agentboard doctor` warns when `conventions/` is empty after activation
- [x] `bash tests/unit.sh` passes (PASS: unit)
- [x] Committed and tagged as v1.5.7
- [ ] `.platform/memory/log.md` appended
- [ ] User confirms done

## Key decisions
2026-04-18 — Use awk prepend-after-separator for log.md instead of temp-file swap — simpler, no partial-write risk, matches the existing `---` separator already in the template

## Resume state

- **Last updated:** 2026-04-18 — by claude-code
- **What just happened:** Both fixes implemented, tests green, tagged v1.5.7
- **Current focus:** Awaiting user sign-off
- **Next action:** User confirms → append to log.md → close stream
- **Blockers:** none

## Progress log

2026-04-18 14:00 — Implemented post-commit prepend fix and doctor activation quality checks; all unit tests pass; committed as v1.5.7

## Open questions
_none_
