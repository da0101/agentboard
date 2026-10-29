#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_dm_fixture() {
  DM_DIR="$(mktemp -d)"
  printf '{}\n' > "$DM_DIR/package.json"
  make_git_repo "$DM_DIR" main; commit_all "$DM_DIR" initial
  init_project_fixture "$DM_DIR"
  cat > "$DM_DIR/.platform/repos.md" <<'EOT'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
| web-app | ../web | React | web.md |
EOT
}

dm_card() { # slug repos created updated related ; body on stdin
  { printf -- '---\ndomain_id: dom-%s\nslug: %s\nstatus: active\nrepo_ids: [%s]\nrelated_domain_slugs: [%s]\ncreated_at: %s\nupdated_at: %s\n---\n\n' "$1" "$1" "$2" "$5" "$3" "$4"; cat; } > "$DM_DIR/.platform/domains/$1.md"
}

seed_cards() {
  dm_card plans "api-server" 2026-01-10 2026-03-01 "pdfs, billing" <<'EOT'
# Domain: Care Plans

Care plans group goals for a patient.

## Backend (api-server)
- `CarePlan` model lives in `plans/models.py`

## Web (web-app)
- Plan editor `src/Plan.tsx`
EOT
  dm_card pdfs "web-app" 2026-02-01 2026-05-09 "plans" <<'EOT'
# Care plan PDFs

How practitioners export a plan as PDF.

## Backend (api-server)
- Renderer in `plans/pdf.py`

## Web (web-app)
- Download button in `src/PdfButton.tsx`
EOT
  dm_card admin "api-server, web-app" 2026-01-01 2026-02-02 "" <<'EOT'
# Plan admin stability

Only an intro paragraph, no sections at all.
EOT
  dm_card billing "api-server" 2026-01-01 2026-01-02 "plans" <<'EOT'
# Billing
Mentions the plans card.
EOT
}

test_merge_keeps_every_line_and_prefixes_source_sections() {
  local output f
  setup_dm_fixture; seed_cards
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  assert_status "$RUN_STATUS" 0
  f="$DM_DIR/.platform/domains/plans.md"
  assert_file_contains "$f" "## Backend (api-server)"                         # target's own sections untouched
  assert_file_contains "$f" "## Care plan PDFs — Backend (api-server)"        # source sections keep layer names
  assert_file_contains "$f" "## Care plan PDFs — Web (web-app)"
  assert_file_contains "$f" "## Care plan PDFs — overview"
  assert_file_contains "$f" "## Plan admin stability — overview"
  assert_file_contains "$f" "Renderer in \`plans/pdf.py\`"
  assert_file_contains "$f" "Only an intro paragraph, no sections at all."
  assert_file_contains "$f" "Care plans group goals for a patient."
  assert_eq "$(grep -c '^# ' "$f")" "1"                                        # one H1 only
}

test_merged_frontmatter_unions_repos_and_widens_dates() {
  local output f
  setup_dm_fixture; seed_cards
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  f="$DM_DIR/.platform/domains/plans.md"
  assert_file_contains "$f" "domain_id: dom-plans"
  assert_file_contains "$f" "repo_ids: [api-server, web-app]"
  assert_file_contains "$f" "created_at: 2026-01-01"
  assert_file_contains "$f" "updated_at: 2026-05-09"
  assert_file_contains "$f" "related_domain_slugs: [billing]"                 # merged slugs removed
}

test_layer_recall_still_finds_every_merged_backend_section() {
  local output
  setup_dm_fixture; seed_cards
  run_cli_capture output "$DM_DIR" domain merge plans pdfs --apply
  run_cli_capture output "$DM_DIR" recall plans --layer backend --no-related
  assert_contains "$output" "plans/models.py"
  assert_contains "$output" "plans/pdf.py"
  assert_not_contains "$output" "PdfButton"
}

test_sources_are_removed_and_backed_up() {
  local output cold
  setup_dm_fixture; seed_cards
  export AGENTBOARD_COLD_DIR="$(mktemp -d)"
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  [[ ! -e "$DM_DIR/.platform/domains/pdfs.md" && ! -e "$DM_DIR/.platform/domains/admin.md" ]] || fail "sources should be removed"
  [[ -f "$DM_DIR/.platform/domains/plans.md" ]] || fail "target missing"
  cold="$(ls -d "$AGENTBOARD_COLD_DIR"/*/domain-merge-* | tail -1)"
  [[ -f "$cold/pdfs.md" && -f "$cold/admin.md" && -f "$cold/plans.md" ]] || fail "originals not backed up"
}

test_references_are_rewritten_everywhere() {
  local output
  setup_dm_fixture; seed_cards
  ( cd "$DM_DIR" && "$TEST_ROOT/bin/ab" new-stream pdf-export --domain pdfs --repo api-server --base-branch main --branch feat/pdf >/dev/null )
  sed -i.bak 's/^domain_slugs: .*/domain_slugs: [pdfs, plans, admin]/' "$DM_DIR/.platform/work/pdf-export.md" && rm -f "$DM_DIR/.platform/work/pdf-export.md.bak"
  printf -- '- `.platform/domains/pdfs.md` — pdf export\n' >> "$DM_DIR/.platform/work/BRIEF.md"
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  assert_file_contains "$DM_DIR/.platform/work/pdf-export.md" "domain_slugs: [plans]"          # rewritten and de-duplicated
  assert_file_contains "$DM_DIR/.platform/work/BRIEF.md" ".platform/domains/plans.md"
  assert_file_not_contains "$DM_DIR/.platform/work/BRIEF.md" "domains/pdfs.md"
  assert_file_contains "$DM_DIR/.platform/domains/billing.md" "related_domain_slugs: [plans]"
}

test_a_card_never_lists_itself_as_related_after_a_merge() {
  local output
  setup_dm_fixture; seed_cards
  dm_card pdfs "web-app" 2026-02-01 2026-05-09 "plans, admin" <<'EOT'
# Care plan PDFs
Body.
EOT
  run_cli_capture output "$DM_DIR" domain merge plans pdfs --apply
  assert_file_not_contains "$DM_DIR/.platform/domains/plans.md" "plans, plans"
  [[ "$(grep '^related_domain_slugs:' "$DM_DIR/.platform/domains/plans.md")" != *"plans"* ]] || fail "target lists itself as related"
}

test_a_new_target_slug_is_built_from_its_sources() {
  local output f
  setup_dm_fixture; seed_cards
  run_cli_capture output "$DM_DIR" domain merge care-plans plans pdfs --title "Care plans" --apply
  f="$DM_DIR/.platform/domains/care-plans.md"
  assert_file_contains "$f" "# Domain: Care plans"
  assert_file_contains "$f" "## Care Plans — Backend (api-server)"
  assert_file_contains "$f" "## Care plan PDFs — Backend (api-server)"
  [[ ! -e "$DM_DIR/.platform/domains/plans.md" && ! -e "$DM_DIR/.platform/domains/pdfs.md" ]] || fail "all sources should be gone"
}

test_preview_writes_nothing() {
  local output before
  setup_dm_fixture; seed_cards
  before="$(cat "$DM_DIR"/.platform/domains/*.md | shasum)"
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin
  assert_contains "$output" "preview"
  assert_contains "$output" "plans pdfs admin"
  assert_eq "$(cat "$DM_DIR"/.platform/domains/*.md | shasum)" "$before"
}

test_unknown_sources_and_bad_slugs_are_refused() {
  local output
  setup_dm_fixture; seed_cards
  run_cli_capture output "$DM_DIR" domain merge plans nonexistent
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown source should fail"
  assert_contains "$output" "No such card"
  run_cli_capture output "$DM_DIR" domain merge "Bad Slug" pdfs
  [[ "$RUN_STATUS" -ne 0 ]] || fail "bad slug should fail"
}

test_doctor_has_no_domain_or_stream_errors_after_a_merge() {
  local output
  setup_dm_fixture; seed_cards
  ( cd "$DM_DIR" && "$TEST_ROOT/bin/ab" new-stream pdf-export --domain pdfs --repo api-server --base-branch main --branch feat/pdf >/dev/null )
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  run_cli_capture output "$DM_DIR" doctor
  assert_not_contains "$output" "references missing domain"
  assert_not_contains "$output" "unknown domain"
  assert_not_contains "$output" "missing frontmatter key"
}

test_no_content_line_of_any_source_is_lost() {
  local output c line missing=0 merged
  setup_dm_fixture; seed_cards
  mkdir -p "$DM_DIR/orig"; cp "$DM_DIR"/.platform/domains/{plans,pdfs,admin}.md "$DM_DIR/orig/"
  run_cli_capture output "$DM_DIR" domain merge plans pdfs admin --apply
  merged="$DM_DIR/.platform/domains/plans.md"
  for c in plans pdfs admin; do
    while IFS= read -r line; do
      grep -qF -- "$line" "$merged" || { echo "LOST from $c: $line" >&2; missing=$((missing + 1)); }
    done < <(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {f=0; next} !f' "$DM_DIR/orig/$c.md" | grep -vE '^[[:space:]]*$|^#')
  done
  assert_eq "$missing" "0"
}

test_merge_keeps_every_line_and_prefixes_source_sections
test_merged_frontmatter_unions_repos_and_widens_dates
test_layer_recall_still_finds_every_merged_backend_section
test_sources_are_removed_and_backed_up
test_references_are_rewritten_everywhere
test_a_card_never_lists_itself_as_related_after_a_merge
test_a_new_target_slug_is_built_from_its_sources
test_preview_writes_nothing
test_unknown_sources_and_bad_slugs_are_refused
test_doctor_has_no_domain_or_stream_errors_after_a_merge
test_no_content_line_of_any_source_is_lost
