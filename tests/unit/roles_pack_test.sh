#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

ROLES_DIR="$TEST_ROOT/templates/platform/roles"
INDEX="$ROLES_DIR/INDEX.md"

# The shipped role pack — alphabetical, one slug per word.
EXPECTED_SLUGS="backend-architect code-auditor debugger frontend-engineer pair-programmer perf-engineer refactor-architect startup-mvp"

# pack_role_files — one role file path per line, skipping INDEX.md
pack_role_files() {
  local f
  for f in "$ROLES_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "INDEX.md" ]] && continue
    printf '%s\n' "$f"
  done
  return 0
}

# pack_frontmatter <file> <key> — frontmatter value, surrounding quotes stripped.
# Deliberately independent of the CLI's frontmatter parser so this contract
# test keeps watching the templates even if the parser regresses.
# (No `head` here — core/base.sh shadows it with a header-printing function.)
pack_frontmatter() {
  local value
  value="$(sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*//p" | sed -n '1p')"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# INDEX.md contract
# ---------------------------------------------------------------------------

test_index_exists_with_roles_markers() {
  [[ -f "$INDEX" ]] || fail "$INDEX missing"
  assert_file_contains "$INDEX" "<!-- agentboard:roles:begin -->"
  assert_file_contains "$INDEX" "<!-- agentboard:roles:end -->"
}

test_index_routing_table_lists_exactly_the_shipped_slugs() {
  local actual expected
  # Routing-table rows start with a backticked slug: | `startup-mvp` | …
  actual="$(sed -n 's/^| `\([a-z-]*\)` |.*/\1/p' "$INDEX" | sort | tr '\n' ' ')"
  expected="$(printf '%s\n' $EXPECTED_SLUGS | sort | tr '\n' ' ')"
  assert_eq "$actual" "$expected"
}

test_index_routing_table_matches_files_on_disk() {
  local from_disk expected
  from_disk="$(pack_role_files | sed 's|.*/||; s|\.md$||' | sort | tr '\n' ' ')"
  expected="$(printf '%s\n' $EXPECTED_SLUGS | sort | tr '\n' ' ')"
  assert_eq "$from_disk" "$expected"
}

# ---------------------------------------------------------------------------
# Role file frontmatter contract
# ---------------------------------------------------------------------------

test_every_role_has_complete_frontmatter() {
  local f key value
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    for key in slug name label ansi_color mission; do
      value="$(pack_frontmatter "$f" "$key")"
      [[ -n "$value" ]] || fail "$f: frontmatter key '$key' missing or empty"
    done
  done < <(pack_role_files)
}

test_every_role_slug_matches_filename() {
  local f slug
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    slug="$(pack_frontmatter "$f" slug)"
    assert_eq "$slug" "$(basename "$f" .md)"
  done < <(pack_role_files)
}

test_every_role_label_follows_role_slug_convention() {
  local f slug label
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    slug="$(pack_frontmatter "$f" slug)"
    label="$(pack_frontmatter "$f" label)"
    assert_eq "$label" "[role:$slug]"
  done < <(pack_role_files)
}

# ---------------------------------------------------------------------------
# Role file section contract
# ---------------------------------------------------------------------------

test_every_role_has_required_sections() {
  local f section
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # Prefix match: some roles extend the heading ("## Deliverables — …").
    for section in "## Identity" "## Expertise" "## Process" "## Deliverables" "## Constraints" "## Label"; do
      grep -q "^$section" "$f" || fail "$f: missing required section '$section'"
    done
  done < <(pack_role_files)
}

# ---------------------------------------------------------------------------
# Stack-agnostic guard (CLAUDE.md hard rule 3)
# ---------------------------------------------------------------------------

test_role_pack_is_stack_agnostic() {
  local hits
  hits="$(grep -REn 'React|Django|Next\.js|Vue|Flutter|Express|Rails' "$ROLES_DIR" || true)"
  [[ -z "$hits" ]] || fail "role pack must be stack-agnostic, found: $hits"
}

# ---------------------------------------------------------------------------
# Root entry templates reference role activation
# ---------------------------------------------------------------------------

test_all_entry_templates_reference_role_activation() {
  local t
  for t in \
    "$TEST_ROOT/templates/root/CLAUDE.md.template" \
    "$TEST_ROOT/templates/root/CLAUDE.md.hub.template" \
    "$TEST_ROOT/templates/root/AGENTS.md.template" \
    "$TEST_ROOT/templates/root/GEMINI.md.template"
  do
    [[ -f "$t" ]] || fail "$t missing"
    assert_file_contains "$t" "Role activation"
    assert_file_contains "$t" ".platform/roles/INDEX.md"
    # No-confident-match fallback must point at the default role
    assert_file_contains "$t" "pair-programmer"
  done
}

# ---------------------------------------------------------------------------
# Invocations
# ---------------------------------------------------------------------------

test_index_exists_with_roles_markers
test_index_routing_table_lists_exactly_the_shipped_slugs
test_index_routing_table_matches_files_on_disk
test_every_role_has_complete_frontmatter
test_every_role_slug_matches_filename
test_every_role_label_follows_role_slug_convention
test_every_role_has_required_sections
test_role_pack_is_stack_agnostic
test_all_entry_templates_reference_role_activation
