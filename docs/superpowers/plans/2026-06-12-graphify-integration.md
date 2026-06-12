# Graphify Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate graphify into agentboard — optional CLI prompt at `ab init` time plus an `ab-graphify` skill deployed to all three provider dirs (Claude Code, Codex, Gemini CLI).

**Architecture:** New `lib/agentboard/commands/graphify_prompt.sh` holds the detection + prompt logic (called from `cmd_init`); a new `templates/skills/ab-graphify/SKILL.md` deploys via `ab update`; all three root templates and `ACTIVATE.md` gain the graphify optional step and skill reference.

**Tech Stack:** Bash 3.2+, existing `ask_yes_no` / `ok` / `say` / `dim` helpers from `lib/agentboard/core/base.sh`

---

### Task 1: Create `graphify_prompt.sh` with tests

**Files:**
- Create: `lib/agentboard/commands/graphify_prompt.sh`
- Create: `tests/unit/graphify_prompt_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/graphify_prompt_test.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# Helper: create a temp bin dir with or without a fake graphify script
# ---------------------------------------------------------------------------
_fake_bin_with_graphify() {
  local tmpbin="$1"
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
mkdir -p graphify-out
printf "stub\n" > graphify-out/GRAPH_REPORT.md
exit 0
EOF
  chmod +x "$tmpbin/graphify"
}

_fake_bin_failing_graphify() {
  local tmpbin="$1"
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$tmpbin/graphify"
}

# ---------------------------------------------------------------------------
# test: graphify absent → tip printed, no prompt, exit 0
# ---------------------------------------------------------------------------
test_graphify_absent_prints_tip() {
  local output tmpbin
  tmpbin="$(mktemp -d)"
  # PATH has no graphify — use a clean bin with only standard tools
  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    _graphify_maybe_prompt "/tmp/fake-target"
  '
  assert_contains "$output" "uv tool install graphifyy"
  assert_not_contains "$output" "build a knowledge graph"
  rm -rf "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer N → no graphify run
# ---------------------------------------------------------------------------
test_graphify_present_answer_no() {
  local output tmpdir tmpbin
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  # Fake graphify that fails if called
  cat > "$tmpbin/graphify" <<'EOF'
#!/usr/bin/env bash
echo "ERROR: graphify should not have been called" >&2
exit 99
EOF
  chmod +x "$tmpbin/graphify"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    printf "N\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  assert_not_contains "$output" "Running graphify"
  assert_not_contains "$output" "should not have been called"
  rm -rf "$tmpdir" "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer Y, graphify succeeds → .platform/graphify/ created
# ---------------------------------------------------------------------------
test_graphify_present_answer_yes_success() {
  local tmpdir tmpbin output
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  mkdir -p "$tmpdir/.platform"
  _fake_bin_with_graphify "$tmpbin"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    cd "'"$tmpdir"'"
    printf "Y\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  [[ -d "$tmpdir/.platform/graphify" ]] \
    || fail "expected .platform/graphify/ to be created"
  [[ -f "$tmpdir/.platform/graphify/GRAPH_REPORT.md" ]] \
    || fail "expected GRAPH_REPORT.md inside .platform/graphify/"
  assert_contains "$output" "Knowledge graph"
  rm -rf "$tmpdir" "$tmpbin"
}

# ---------------------------------------------------------------------------
# test: graphify present, answer Y, graphify exits non-zero → warning, exit 0
# ---------------------------------------------------------------------------
test_graphify_present_answer_yes_failure() {
  local tmpdir tmpbin output
  tmpdir="$(mktemp -d)"
  tmpbin="$(mktemp -d)"
  mkdir -p "$tmpdir/.platform"
  _fake_bin_failing_graphify "$tmpbin"

  run_and_capture output bash -c '
    export PATH="'"$tmpbin"':/usr/bin:/bin"
    source "'"$TEST_ROOT"'/lib/agentboard/core/base.sh"
    source "'"$TEST_ROOT"'/lib/agentboard/commands/graphify_prompt.sh"
    cd "'"$tmpdir"'"
    printf "Y\n" | _graphify_maybe_prompt "'"$tmpdir"'"
  '
  assert_contains "$output" "Warning"
  assert_not_contains "$output" "Knowledge graph"
  rm -rf "$tmpdir" "$tmpbin"
}

test_graphify_absent_prints_tip
test_graphify_present_answer_no
test_graphify_present_answer_yes_success
test_graphify_present_answer_yes_failure
```

- [ ] **Step 2: Run test to verify it fails (file missing)**

```bash
bash tests/unit/graphify_prompt_test.sh
```

Expected: error — `graphify_prompt.sh: No such file or directory` or source failure.

- [ ] **Step 3: Write `lib/agentboard/commands/graphify_prompt.sh`**

```bash
#!/usr/bin/env bash
# Optional graphify detection and prompt — called from cmd_init.
# Detects graphify on PATH, prompts y/N if found, prints install tip if not.
# Never fails: all code paths return 0 so ab init always completes.

_graphify_maybe_prompt() {
  local target="${1:-.}"

  if ! command -v graphify >/dev/null 2>&1; then
    say
    dim "  Tip: install graphify to map this codebase into a queryable knowledge graph."
    dim "       uv tool install graphifyy && graphify install"
    return 0
  fi

  say
  if ! ask_yes_no "Graphify detected — build a knowledge graph now?"; then
    return 0
  fi

  say
  printf '  Running graphify…\n'
  local dest_dir="$target/.platform/graphify"

  if graphify . 2>&1 | sed 's/^/  /'; then
    mkdir -p "$dest_dir"
    if [[ -d "graphify-out" ]]; then
      cp -R "graphify-out/." "$dest_dir/"
      rm -rf "graphify-out"
    fi
    ok "Knowledge graph → ${C_CYAN}.platform/graphify/${C_RESET}"
    dim "  Open graph.html in a browser, or ask the LLM about GRAPH_REPORT.md."
  else
    printf '  %sWarning: graphify exited with an error — skipped.%s\n' "$C_YELLOW" "$C_RESET"
  fi
  say
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash tests/unit/graphify_prompt_test.sh
```

Expected: all four tests pass, no FAIL output.

- [ ] **Step 5: Verify file stays under 300 lines**

```bash
wc -l lib/agentboard/commands/graphify_prompt.sh
```

Expected: under 50 lines (well within the 300-line cap).

- [ ] **Step 6: Commit**

```bash
git add lib/agentboard/commands/graphify_prompt.sh tests/unit/graphify_prompt_test.sh
git commit -m "feat: add _graphify_maybe_prompt helper with tests"
```

---

### Task 2: Wire `graphify_prompt.sh` into the CLI

**Files:**
- Modify: `bin/agentboard:34` — add source line after init.sh
- Modify: `lib/agentboard/commands/init.sh:310` — replace blank line with function call

- [ ] **Step 1: Add source line to `bin/agentboard`**

In `bin/agentboard`, after line 34 (`source "$AGENTBOARD_ROOT/lib/agentboard/commands/init.sh"`), add:

```bash
source "$AGENTBOARD_ROOT/lib/agentboard/commands/graphify_prompt.sh"
```

- [ ] **Step 2: Add function call to `init.sh`**

In `lib/agentboard/commands/init.sh`, line 310 is a blank line between two `say` calls, just before the "Next step: activate" banner. Replace that blank line with:

```bash
  _graphify_maybe_prompt "$target"
```

The surrounding context (lines 308–313) should look like:

```bash
  fi
  say

  _graphify_maybe_prompt "$target"
  if (( hub_mode )); then
```

- [ ] **Step 3: Verify init.sh has not grown past 348 lines**

```bash
wc -l lib/agentboard/commands/init.sh
bash tests/unit/file_size_ratchet_test.sh
```

Expected: `348` (or fewer), ratchet test passes.

- [ ] **Step 4: Smoke-test `ab init` with no graphify installed**

In a temp dir with no graphify on PATH:

```bash
tmpdir=$(mktemp -d)
printf '\n\n' | bash -c "cd '$tmpdir' && PATH=/usr/bin:/bin '$PWD/bin/ab' init"
```

Expected: init completes, tip line about `uv tool install graphifyy` is printed, `.platform/` is created normally.

- [ ] **Step 5: Run full unit test suite**

```bash
bash tests/unit.sh
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/agentboard lib/agentboard/commands/init.sh
git commit -m "feat: wire _graphify_maybe_prompt into ab init"
```

---

### Task 3: Create `templates/skills/ab-graphify/SKILL.md`

**Files:**
- Create: `templates/skills/ab-graphify/SKILL.md`

- [ ] **Step 1: Write the skill file**

Create `templates/skills/ab-graphify/SKILL.md`:

```markdown
# ab-graphify

Graphify maps your entire codebase into a queryable knowledge graph stored at
`.platform/graphify/`. Use this skill to build or refresh the graph, and to
reference it during research.

## What it produces

After running, `.platform/graphify/` contains:
- `graph.html` — interactive browser visualization (click nodes, filter, search)
- `GRAPH_REPORT.md` — key concepts, cross-cutting patterns, surprising connections, suggested questions
- `graph.json` — the full graph; query it any time without re-reading source files

## When to suggest running graphify

1. **After `ab init`** — if the init prompt was skipped or graphify was installed later.
2. **After `ab rescan`** — when ≥5 files changed, the graph may be stale.
3. **Before starting a new stream** that touches unfamiliar parts of the repo.

## How to invoke

Run via your shell tool (works in Claude Code, Codex, Gemini CLI, and any other AI agent):

```bash
graphify .
```

If graphify outputs to `graphify-out/` (its default), move the output:

```bash
mkdir -p .platform/graphify
cp -R graphify-out/. .platform/graphify/
rm -rf graphify-out
```

## How to use the output

During `ab-research`, read `.platform/graphify/GRAPH_REPORT.md` **first** — it surfaces
cross-cutting patterns and surprising connections that grep misses. Use `graph.json`
for precise dependency queries.

## Not installed?

If `graphify` is not found, tell the user:

```bash
uv tool install graphifyy && graphify install
```

Then re-run `graphify .` from the project root.
```

- [ ] **Step 2: Verify the skill file is well-formed**

```bash
head -3 templates/skills/ab-graphify/SKILL.md
```

Expected: starts with `# ab-graphify`.

- [ ] **Step 3: Commit**

```bash
git add templates/skills/ab-graphify/SKILL.md
git commit -m "feat: add ab-graphify skill template"
```

---

### Task 4: Update `ACTIVATE.md` — optional graphify step + skill table entry

**Files:**
- Modify: `templates/platform/ACTIVATE.md`

- [ ] **Step 1: Add optional graphify step after Step 3**

In `templates/platform/ACTIVATE.md`, after the `## Step 3 — Fill the .platform/ pack` section (just before `## Step 4`), add:

```markdown
## Step 3b — Knowledge graph (optional)

If `graphify --version` returns a version number, build the knowledge graph now:

```bash
graphify .
mkdir -p .platform/graphify
cp -R graphify-out/. .platform/graphify/ && rm -rf graphify-out
```

This takes ~30 seconds and writes `.platform/graphify/GRAPH_REPORT.md` — a summary of
key concepts, cross-cutting patterns, and surprising connections. Reference it during
`ab-research` instead of grepping individual files.

If graphify is not installed, suggest: `uv tool install graphifyy && graphify install`
then skip this step.
```

- [ ] **Step 2: Add `ab-graphify` to the skills table**

In `templates/platform/ACTIVATE.md`, find the skills table under `## Skills available to you`. Add a new row:

```markdown
| `ab-graphify` | Build or refresh the codebase knowledge graph. Reference `GRAPH_REPORT.md` during research. |
```

- [ ] **Step 3: Verify the file looks correct**

```bash
grep -n "ab-graphify\|Step 3b\|Knowledge graph" templates/platform/ACTIVATE.md
```

Expected: lines for `Step 3b`, `Knowledge graph`, and `ab-graphify` all appear.

- [ ] **Step 4: Commit**

```bash
git add templates/platform/ACTIVATE.md
git commit -m "feat: add optional graphify step and ab-graphify to ACTIVATE.md"
```

---

### Task 5: Update all three root templates — skills list

**Files:**
- Modify: `templates/root/CLAUDE.md.template:210`
- Modify: `templates/root/AGENTS.md.template:180`
- Modify: `templates/root/GEMINI.md.template:178`

Each template has a line like:

```
`ab-triage`, `ab-workflow`, `ab-research`, `ab-pm`, `ab-architect`, `ab-test-writer`, `ab-security`, `ab-qa`, `ab-review`, `ab-debug`
```

- [ ] **Step 1: Update `CLAUDE.md.template`**

Replace the skills list line (line 210) with:

```
`ab-triage`, `ab-workflow`, `ab-research`, `ab-pm`, `ab-architect`, `ab-test-writer`, `ab-security`, `ab-qa`, `ab-review`, `ab-debug`, `ab-graphify`
```

- [ ] **Step 2: Update `AGENTS.md.template`**

Replace the skills list line (line 180) with the same string:

```
`ab-triage`, `ab-workflow`, `ab-research`, `ab-pm`, `ab-architect`, `ab-test-writer`, `ab-security`, `ab-qa`, `ab-review`, `ab-debug`, `ab-graphify`
```

- [ ] **Step 3: Update `GEMINI.md.template`**

Replace the skills list line (line 178) with the same string:

```
`ab-triage`, `ab-workflow`, `ab-research`, `ab-pm`, `ab-architect`, `ab-test-writer`, `ab-security`, `ab-qa`, `ab-review`, `ab-debug`, `ab-graphify`
```

- [ ] **Step 4: Verify all three files updated**

```bash
grep "ab-graphify" templates/root/CLAUDE.md.template templates/root/AGENTS.md.template templates/root/GEMINI.md.template
```

Expected: one match per file, all three files shown.

- [ ] **Step 5: Commit**

```bash
git add templates/root/CLAUDE.md.template templates/root/AGENTS.md.template templates/root/GEMINI.md.template
git commit -m "feat: add ab-graphify to skills list in all three root templates"
```

---

### Task 6: Deploy skill to the agentboard dogfood project + run full test suite

**Files:**
- Modify: `.claude/skills/ab-graphify/SKILL.md` (created by ab update)
- Modify: `.agents/skills/ab-graphify/SKILL.md` (created by ab update)

- [ ] **Step 1: Run `ab update` in this repo to deploy the new skill**

```bash
bin/ab update
```

Expected: output shows `+ skills/ab-graphify  (new)` for both `.claude/skills/` and `.agents/skills/`.

- [ ] **Step 2: Verify the skill was deployed**

```bash
ls .claude/skills/ab-graphify/SKILL.md .agents/skills/ab-graphify/SKILL.md
```

Expected: both files exist.

- [ ] **Step 3: Run the full test suite**

```bash
bash tests/unit.sh
```

Expected: all tests pass including `file_size_ratchet_test` and the new `graphify_prompt_test`.

- [ ] **Step 4: Commit deployed skill files**

```bash
git add .claude/skills/ab-graphify .agents/skills/ab-graphify
git commit -m "chore: dogfood ab update — deploy ab-graphify skill to agentboard itself"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run integration test — full `ab init` with piped input (no graphify)**

```bash
tmpdir=$(mktemp -d)
run_output=$(printf '\n\n' | bash -c "cd '$tmpdir' && PATH=/usr/bin:/bin '$PWD/bin/ab' init" 2>&1)
echo "$run_output" | grep -i "graphify" || echo "(no graphify mention — OK if graphify not installed)"
[[ -d "$tmpdir/.platform" ]] && echo "PASS: .platform/ created"
rm -rf "$tmpdir"
```

Expected: `.platform/` created, tip line present if graphify is absent from the stripped PATH.

- [ ] **Step 2: Confirm ratchet still passes**

```bash
bash tests/unit/file_size_ratchet_test.sh
```

Expected: PASS.

- [ ] **Step 3: Confirm skill appears in `ab update` dry-run output for a fresh project**

```bash
tmpdir=$(mktemp -d)
printf '\n\n' | bash -c "cd '$tmpdir' && '$PWD/bin/ab' init" >/dev/null 2>&1
(cd "$tmpdir" && "$OLDPWD/bin/ab" update --dry-run 2>&1) | grep "ab-graphify" || echo "PASS: no update needed (already current)"
rm -rf "$tmpdir"
```

Expected: skill is already in place after init (no update needed), or dry-run shows it would be added.

- [ ] **Step 4: Log to `.platform/memory/log.md`**

Append one line:

```
2026-06-12 — graphify-integration stream — shipped ab-graphify skill + init prompt + ACTIVATE.md step across all three provider templates
```

- [ ] **Step 5: Final commit if anything remains uncommitted**

```bash
git status
# Only commit if there are uncommitted changes
git add .platform/memory/log.md
git commit -m "chore: log graphify-integration stream completion"
```
