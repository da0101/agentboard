# -----------------------------------------------------------------------------
# ab repair domains [--apply] — normalize domain-card frontmatter.
#
# Doctor requires domain_id, slug, status, repo_ids, created_at, updated_at on
# every .platform/domains/*.md. Cards written by hand or by older agents often
# have none, or use other keys (domain / repos / last_updated). This fills ONLY
# what is missing and never rewrites the card body:
#   slug        filename            domain_id  dom-<slug>        status  active
#   repo_ids    existing repo_ids / repos, else the registered repos (repos.md,
#               by id or folder name) the card text mentions
#   updated_at  existing / last_updated / "Last updated: YYYY-MM-DD" / last git
#               commit / file mtime;  created_at: existing / first git commit
# Cards whose repos cannot be inferred are reported, not guessed. Preview by
# default; --apply writes (originals are copied to the cold store first).
# Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

# _rd_block <file> — frontmatter lines (without the --- fences), if any
_rd_block() { awk 'NR == 1 && /^---[ \t]*$/ { f = 1; next } f && /^---[ \t]*$/ { exit } f { print }' "$1"; }

# _rd_body <file> — everything after the frontmatter
_rd_body() {
  awk 'NR == 1 && /^---[ \t]*$/ { f = 1; next } f && /^---[ \t]*$/ { f = 0; next } !f { print }' "$1" | awk 'NF || seen { seen = 1; print }'
}

# _rd_get <block> <key...> — first non-empty value among the alias keys
_rd_get() {
  local block="$1" k v; shift
  for k in "$@"; do
    v="$(printf '%s\n' "$block" | sed -n "s/^${k}:[[:space:]]*//p" | awk 'NR == 1' | sed 's/^["'"'"']//; s/["'"'"']$//')"
    [[ -n "$v" && "$v" != "[]" ]] && { printf '%s' "$v"; return 0; }
  done
  return 0
}

# _rd_infer_repos <card> — registered repo ids mentioned in the card, as "a, b"
_rd_infer_repos() {
  local card="$1" rows row id path name out="" text
  [[ -f ./.platform/repos.md ]] || return 0
  rows="$(repo_rows_from_registry ./.platform/repos.md)"; text="$(tr '[:upper:]' '[:lower:]' < "$card")"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    id="${row%%|*}"; path="$(printf '%s' "$row" | cut -d'|' -f2)"; name="$(basename "$path" | tr '[:upper:]' '[:lower:]')"
    if printf '%s' "$text" | grep -qF -- "$id" || { [[ -n "$name" && "$name" != "$id" ]] && printf '%s' "$text" | grep -qF -- "$name"; }; then
      out="${out:+$out, }$id"
    fi
  done <<< "$rows"
  printf '%s' "$out"
}

_rd_date_ok() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; }

cmd_repair_domains() {
  local apply=0 f slug block status repos updated created dom_id note changed=0 unresolved=0 total=0 cold out extra
  [[ "${1:-}" == "--apply" ]] && apply=1
  [[ -d ./.platform/domains ]] || die "No .platform/domains/ found."
  cold="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")/repair-domains-$(today)"
  printf '\n%s%sab repair domains%s %s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$( (( apply )) && echo '(applying)' || echo '(preview — add --apply to write)')"
  for f in ./.platform/domains/*.md; do
    [[ -f "$f" ]] || continue
    slug="$(basename "$f" .md)"; [[ "$slug" == TEMPLATE ]] && continue
    total=$((total + 1)); block="$(_rd_block "$f")"; note=""

    dom_id="dom-${slug}"
    status="$(_rd_get "$block" status)"; [[ -n "$status" ]] || status="active"
    repos="$(_rd_get "$block" repo_ids repos)"; repos="${repos#[}"; repos="${repos%]}"
    if [[ -z "$repos" ]]; then repos="$(_rd_infer_repos "$f")"; [[ -n "$repos" ]] && note="$note repo_ids inferred from text;"; fi
    updated="$(_rd_get "$block" updated_at last_updated)"
    _rd_date_ok "$updated" || updated="$({ grep -m1 -iE '^(\*\*)?last updated:?(\*\*)?:? *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" || true; } | { grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true; } | awk 'NR == 1')"
    _rd_date_ok "${updated:-x}" || updated="$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)"
    _rd_date_ok "${updated:-x}" || updated="$(date -r "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")" +%Y-%m-%d 2>/dev/null || true)"
    created="$(_rd_get "$block" created_at)"
    _rd_date_ok "${created:-x}" || created="$({ git log --diff-filter=A --format=%cs -- "$f" 2>/dev/null || true; } | awk 'END { print }')"
    _rd_date_ok "${created:-x}" || created="$updated"

    # already complete and canonical -> leave alone
    if [[ "$(_rd_get "$block" domain_id)" == "$dom_id" && "$(_rd_get "$block" slug)" == "$slug" && -n "$(_rd_get "$block" status)" \
          && -n "$(_rd_get "$block" repo_ids)" && -n "$(_rd_get "$block" created_at)" && -n "$(_rd_get "$block" updated_at)" ]]; then
      continue
    fi
    if [[ -z "$repos" ]]; then
      unresolved=$((unresolved + 1)); printf '  %s? %-42s%s cannot infer repo_ids — add them by hand\n' "$C_YELLOW" "$slug" "$C_RESET"; continue
    fi
    changed=$((changed + 1))
    printf '  ~ %-42s repo_ids=[%s] updated=%s created=%s%s\n' "$slug" "$repos" "$updated" "$created" "$note"
    (( apply )) || continue
    mkdir -p "$cold" && cp -p "$f" "$cold/$slug.md"
    out="$(mktemp)"
    extra="$(printf '%s\n' "$block" | grep -vE '^(domain_id|slug|status|repo_ids|repos|domain|related_domain_slugs|created_at|updated_at|last_updated):' | grep -E '^[A-Za-z_]+:' || true)"
    { printf -- '---\ndomain_id: %s\nslug: %s\nstatus: %s\nrepo_ids: [%s]\nrelated_domain_slugs: %s\ncreated_at: %s\nupdated_at: %s\n' \
        "$dom_id" "$slug" "$status" "$repos" "$(_rd_get "$block" related_domain_slugs)" "$created" "$updated"
      [[ -z "$extra" ]] || printf '%s\n' "$extra"
      printf -- '---\n\n'
      _rd_body "$f"
    } | sed 's/^related_domain_slugs: $/related_domain_slugs: []/' > "$out"
    mv "$out" "$f"
  done
  printf '\n  %d card(s) checked: %d %s, %d unresolved.\n' "$total" "$changed" "$( (( apply )) && echo repaired || echo 'would be repaired')" "$unresolved"
  (( apply )) && (( changed > 0 )) && say "  Originals copied to $cold"
  return 0
}
