---
stream: skills-baseline-testing
status: in-progress
opened: 2026-04-30
closure_approved: false
---

# Stream: Skills Baseline Testing

## Goal
Run pressure scenarios against the top 5 discipline-enforcing ab-* skills WITHOUT the skill loaded. Document what agents naturally do wrong. Patch any skill that doesn't hold under pressure.

## Skills Under Test (priority order)
1. ab-workflow — do agents skip stages under time pressure?
2. ab-debug — do agents write a regression test before fixing?
3. ab-triage — do agents read files before classifying?
4. ab-test-writer — do agents cover edge cases or just happy path?
5. ab-security — do agents follow the full checklist or just skim?

## Method
Each subagent gets a realistic pressure scenario with NO skill loaded. They document every step. Results compared against what the skill requires. Failures → explicit counter added to skill.

## Done Criteria
- [x] 5 pressure scenarios run and logged
- [x] Failures identified per skill
- [x] Skills patched where agent violated rules (ab-debug, ab-security, ab-workflow)
- [x] Re-test: all 3 patched skills now PASS
- [ ] Human sign-off before closing

## Results Log

### ab-workflow — FAIL (structure skipped)
Agent went straight to "read 4 files → advisor call → implement." No triage emitted. No stream registration. No parallel probes. No verification step planned. Questions asked were good but framed as pre-implementation clarification, not Stage 2 interview.
Key violations: Stage 1 (triage not emitted), Stage 1b (no registration), Stage 3 (sequential not parallel), Stage 6 (not planned).

### ab-debug — FAIL (regression test after fix)
Agent formed hypotheses, tested them, found real root cause, fixed it. But regression test was written AFTER the fix (step 25 after step 23). Hard Rule 4 violated. No formal "lock in facts" template at start. No session log to .platform/memory/log.md.
Key violation: regression test must fail before fix exists — test was written after.

### ab-triage — PARTIAL (behavior correct, format wrong)
Agent classified BEFORE reading any files (correct!). But emitted "small additive feature, low risk" informally, not the three-line format: Triage: X / Y / Z + Why + Workflow. The behavioral enforcement works; the format prescription doesn't.
Key violation: format not followed.

### ab-test-writer — PARTIAL (coverage good, structure missing)
29 tests written, good edge-case coverage, ran suite before claiming done. But: no framework detection line emitted, no formal unit classification step, tests written without the prescribed checklist as the explicit guide.
Key violations: Steps 1 and 2 skipped (detection line, unit classification).

### ab-security — FAIL (format and scope declaration missing)
Comprehensive review: 14 categories checked, two real bugs found (sed & injection, shopt leakage), file:line references, what-was-not-checked list. But: no Scope/Threat/Trust boundary declaration at start, checklist not followed in order, findings not in Critical/High/Medium/Low format, no "Checked and clean" section.
Key violations: Scope preamble skipped, report format not followed.
