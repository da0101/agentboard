"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.escapeForDoubleQuotedCli = escapeForDoubleQuotedCli;
exports.buildExplainChangePrompt = buildExplainChangePrompt;
exports.buildRefactorPrompt = buildRefactorPrompt;
function escapeForDoubleQuotedCli(input) {
    return input.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/`/g, "\\`");
}
function buildExplainChangePrompt(input) {
    const diffStat = (input.added ? `+${input.added}` : "") + (input.added && input.deleted ? " / " : "") + (input.deleted ? `-${input.deleted}` : "");
    return `/ab-review

A reviewer is auditing \`${input.absPath}\` and sees ⚠ **${input.totalChanged} lines changed** (${diffStat}).

You made these changes — walk through your decisions clearly and directly. No preamble. Assume the reviewer is a senior engineer.

═══ 1. PROBLEM & APPROACH
What problem were you solving in this file specifically, and why did you choose this approach over the alternatives you considered?

═══ 2. KEY CHANGES — section by section
For each significant block you added or rewrote:
• What was there before (brief)
• What you changed it to
• Why this is strictly better

═══ 3. WHAT WAS REMOVED AND WHY
For every significant deletion: what did you remove, why was it wrong/redundant/dead, and what (if anything) replaces it?

═══ 4. DESIGN DECISIONS
Any non-obvious architectural choices — naming, structure, data flow, abstraction boundaries, dependency direction. State the reasoning and the tradeoff you accepted.

═══ 5. RISK SURFACE
What is the most fragile thing about these changes? Any edge cases, regressions, or coupling risks introduced? What guards did you put in place?

═══ 6. WHAT TO WATCH NEXT
Anything in this file that is still wrong, incomplete, or will need follow-up attention?`;
}
function buildRefactorPrompt(input) {
    const tier = input.lineCount >= 1000 ? "CRITICAL — extreme monolith (1000+ lines)"
        : input.lineCount >= 800 ? "HIGH — large file (800–999 lines)"
            : "MODERATE — growing file (500–799 lines)";
    return `/ab-cleanup

Refactor this file — ${input.lineCount} lines flagged ${tier}:
  ${input.absPath}

Follow every phase of the ab-cleanup protocol. This is a production-grade refactor — Silicon Valley standard.

═══ PHASE 0 — SAFETY NET (before reading a single line of code)
• Run the existing test suite → record baseline: X passing / Y failing / Z skipped
• grep / find every file that imports or references this module
• List every public export — these are the sacred API contract, do NOT rename without full grep verification of zero callers
• Note any runtime-critical paths (called on startup, hot path, etc.)

═══ PHASE 1 — AUDIT (read the ENTIRE file, then classify)
• Map every class, function, and responsibility line-by-line
• Identify: God class/component, >3-level nesting, copy-paste blocks, mixed concerns (UI+logic, IO+transform), side effects inside pure functions, magic numbers/strings
• Classify each violation by type: DRY / SRP / coupling / testability / readability / complexity

═══ PHASE 2 — PLAN  ← STOP HERE AND PRESENT BEFORE ANY CODE CHANGES
For every planned extraction, state:
  • New filename and target directory
  • Lines extracted (source range)
  • Why this is safe (callers unaffected, contract unchanged)
  • Resulting line count for source file + new file (both must be <300 lines)
  • New test(s) required to cover the extracted module

Murphy's Law check: what is the most fragile thing about this refactor? How will you guard against it?

DO NOT proceed to Phase 3 until the plan is approved.

═══ PHASE 3 — EXECUTE (only after plan approval)
• One extraction at a time — tests must pass green after EVERY extraction
• Leave the original file as a thin orchestrator/re-export barrel during transition
• Apply: Single Responsibility, Open/Closed, DRY, Law of Demeter, immutability-first
• Zero magic numbers — extract to named constants with intent-revealing names
• Zero copy-paste — extract to shared utils or helpers
• Every new function: pure where possible, side-effect-free, single responsibility

═══ PHASE 4 — REGRESSION
• Run the FULL test suite — zero new failures allowed
• For every new module created: write minimum 1 happy-path test + 1 edge/error-case test
• Pre-existing failures: flag as pre-existing, never hide, do NOT count as regressions from this refactor
• Explicitly test the path most likely to break under Murphy's Law

═══ PHASE 5 — REPORT
• Before/after line counts for every file touched (table format)
• Complete list of new files created
• Any refactors intentionally skipped — reason required (public API contract, legitimate complexity, etc.)
• Public API contract status: UNCHANGED / EXTENDED (never broken)`;
}
