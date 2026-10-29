#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_rd_fixture() {
  RD_DIR="$(mktemp -d)"
  printf '{}\n' > "$RD_DIR/package.json"
  make_git_repo "$RD_DIR" main
  commit_all "$RD_DIR" initial
  init_project_fixture "$RD_DIR"
  cat > "$RD_DIR/.platform/repos.md" <<'EOT'
# Hub

## Repos

| Repo ID | Path | Stack | Deep reference |
|---|---|---|---|
| api-server | ../ApiServer | Django | api.md |
| web-app | ../web | React | web.md |
EOT
}

card() { # name <stdin body>
  cat > "$RD_DIR/.platform/domains/$1.md"
}

test_card_without_frontmatter_gets_inferred_repos_and_dates() {
  local output f="x"
  setup_rd_fixture
  card orders <<'EOT'
# Orders

Last updated: 2026-09-14

Backend lives in `api-server/orders/models.py`; the UI in `web-app/src/Orders.tsx`.
EOT
  f="$RD_DIR/.platform/domains/orders.md"
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$f" "domain_id: dom-orders"
  assert_file_contains "$f" "slug: orders"
  assert_file_contains "$f" "status: active"
  assert_file_contains "$f" "repo_ids: [api-server, web-app]"
  assert_file_contains "$f" "updated_at: 2026-09-14"
  assert_file_contains "$f" "created_at: "
}

test_repos_are_also_found_by_folder_name() {
  local output f
  setup_rd_fixture
  card billing <<'EOT'
# Billing
Invoices are in `ApiServer/billing/invoice.py`.
EOT
  f="$RD_DIR/.platform/domains/billing.md"
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_file_contains "$f" "repo_ids: [api-server]"
}

test_old_key_names_are_normalized_and_unknown_keys_survive() {
  local output f
  setup_rd_fixture
  card legacy <<'EOT'
---
domain: legacy
repos: [web-app]
last_updated: 2026-05-04
owner: someone-on-the-team
---

# Legacy
Body text.
EOT
  f="$RD_DIR/.platform/domains/legacy.md"
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_file_contains "$f" "repo_ids: [web-app]"
  assert_file_contains "$f" "updated_at: 2026-05-04"
  assert_file_contains "$f" "owner: someone-on-the-team"
  assert_file_not_contains "$f" "last_updated:"
  assert_file_not_contains "$f" "repos:"
}

test_the_card_body_is_left_byte_for_byte_alone() {
  local output f body_before body_after
  setup_rd_fixture
  card keep <<'EOT'
# Keep

## Backend (api-server)
- `orders/models.py` — keep   this   spacing
- a | pipe and a \ backslash

EOT
  f="$RD_DIR/.platform/domains/keep.md"
  body_before="$(cat "$f")"
  run_cli_capture output "$RD_DIR" repair domains --apply
  body_after="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$f" | awk 'NF || s {s=1; print}')"
  assert_eq "$body_after" "$(printf '%s\n' "$body_before" | awk 'NF || s {s=1; print}')"
}

test_complete_cards_are_not_touched() {
  local output f before
  setup_rd_fixture
  card done <<'EOT'
---
domain_id: dom-done
slug: done
status: active
repo_ids: [api-server]
related_domain_slugs: []
created_at: 2026-01-01
updated_at: 2026-02-02
---

# Done
EOT
  f="$RD_DIR/.platform/domains/done.md"; before="$(cat "$f")"
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_eq "$(cat "$f")" "$before"
  assert_contains "$output" "0 repaired"
}

test_unresolvable_cards_are_reported_not_guessed() {
  local output f before
  setup_rd_fixture
  card mystery <<'EOT'
# Mystery
Nothing here names a repo.
EOT
  f="$RD_DIR/.platform/domains/mystery.md"; before="$(cat "$f")"
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_contains "$output" "cannot infer repo_ids"
  assert_contains "$output" "1 unresolved"
  assert_eq "$(cat "$f")" "$before"
}

test_preview_writes_nothing_and_apply_backs_up_originals() {
  local output f before cold
  setup_rd_fixture
  export AGENTBOARD_COLD_DIR="$(mktemp -d)"   # own cold store: other tests also back up an orders.md
  card orders <<'EOT'
# Orders
Uses `api-server/orders/models.py`.
EOT
  f="$RD_DIR/.platform/domains/orders.md"; before="$(cat "$f")"
  run_cli_capture output "$RD_DIR" repair domains
  assert_contains "$output" "preview"
  assert_eq "$(cat "$f")" "$before"
  run_cli_capture output "$RD_DIR" repair domains --apply
  cold="$(ls "$AGENTBOARD_COLD_DIR"/*/repair-domains-*/orders.md | tail -1)"
  assert_eq "$(cat "$cold")" "$before"
}

test_apply_is_idempotent_and_clears_the_doctor_errors() {
  local output
  setup_rd_fixture
  card orders <<'EOT'
# Orders
Uses `api-server/orders/models.py`.
EOT
  run_cli_capture output "$RD_DIR" doctor
  assert_contains "$output" "missing frontmatter key 'domain_id'"
  run_cli_capture output "$RD_DIR" repair domains --apply
  run_cli_capture output "$RD_DIR" repair domains --apply
  assert_contains "$output" "0 repaired"
  run_cli_capture output "$RD_DIR" doctor
  assert_not_contains "$output" "missing frontmatter key"
  assert_not_contains "$output" "missing non-empty frontmatter key"
}

test_card_without_frontmatter_gets_inferred_repos_and_dates
test_repos_are_also_found_by_folder_name
test_old_key_names_are_normalized_and_unknown_keys_survive
test_the_card_body_is_left_byte_for_byte_alone
test_complete_cards_are_not_touched
test_unresolvable_cards_are_reported_not_guessed
test_preview_writes_nothing_and_apply_backs_up_originals
test_apply_is_idempotent_and_clears_the_doctor_errors
