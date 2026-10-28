cmd_close() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      _close_print_help
      return 0
    else
      die "Usage: ab close <stream-slug> [--confirm] [--dry-run]"
    fi
  fi
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local confirm=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) _close_print_help; return 0 ;;
      *) die "Unknown flag for close: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'ab migrate --apply' first."

  if (( ! confirm )); then
    _close_print_harvest_prompt "$slug" "$stream_file"
    return 0
  fi

  if (( ! dry_run )); then
    local _approved; _approved="$(frontmatter_value "$stream_file" "closure_approved")"
    if [[ "$_approved" != "true" ]]; then
      die "closure_approved is not set to true in $stream_file.
  Complete the harvest checklist first:
    ab close $slug
  Then set  closure_approved: true  in the stream file and re-run --confirm."
    fi
  fi

  local today_str agent stage
  today_str="$(today)"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"
  stage="$(mktemp -d)"

  if [[ -z "$(_ck_records "$stream_file")" ]]; then
    warn "No '## Knowledge delta' in $stream_file — domain cards will not be updated."
  else
    say "Knowledge delta -> domain cards$( (( dry_run )) && printf ' (dry run)' || true)"
    _ck_apply "$slug" "$stream_file" "$stage"
    say "  ${CK_ADDED} added, ${CK_REPLACED} replaced, ${CK_REMOVED} removed, ${CK_CARDS_NEW} new card(s), ${CK_MISSING} not found, ${CK_SKIPPED} skipped"
  fi

  if (( dry_run )); then
    rm -rf "$stage"
    printf '%sWould copy%s the stream outside the repo, then remove %s\n' "$C_BOLD" "$C_RESET" "$stream_file"
    printf '%sWould update ACTIVE.md:%s remove stream row\n' "$C_BOLD" "$C_RESET"
    printf '%sWould append closure row to .platform/memory/log.md%s\n' "$C_BOLD" "$C_RESET"
    return 0
  fi

  _ck_commit "$stage"
  rm -rf "$stage"

  # distill reads the live stream file, so it must run before removal.
  # In-process (not via the agentboard binary) so it never silently skips.
  ( cmd_distill "$slug" --quiet ) >/dev/null 2>&1 || true

  # Per-stream lock: don't let a concurrent checkpoint/watch interleave.
  platform_lock_acquire "stream-${slug}" || true
  replace_frontmatter_line "$stream_file" "status" "done"
  replace_frontmatter_line "$stream_file" "closure_approved" "true"
  replace_frontmatter_line "$stream_file" "updated_at" "$today_str"
  local cold qa_n; cold="$(_ck_cold_store "$slug" "$stream_file")"
  qa_n="$(_ck_cold_store_qa "$slug" "$(dirname "$cold")/${slug}-qa")"
  rm -f "$stream_file"
  platform_lock_release "stream-${slug}"

  platform_with_lock "memory-log" _close_append_log "$slug" "$cold" "$today_str" "$agent"
  platform_with_lock "active-md" _close_update_active_registry_status "$slug"

  ok "Stream ${C_BOLD}${slug}${C_RESET} closed. Knowledge merged into domain cards; stream file removed."
  say "  ${C_DIM}Copy kept outside the repo: ${cold}${C_RESET}"
  (( qa_n == 0 )) || say "  ${C_DIM}${qa_n} QA item(s) moved out of the repo with it.${C_RESET}"
  say "  ${C_DIM}Gotchas/playbook/questions not harvested before --confirm are lost from project memory.${C_RESET}"
  if [[ -n "$(_wt_linked "$(_wt_main_path .)" 2>/dev/null)" ]]; then
    say "  ${C_DIM}Linked worktrees exist — review leftovers: ab worktree status (remove merged: ab worktree clean --apply)${C_RESET}"
  fi
}

_close_print_help() {
  cat <<'EOF'
Usage: ab close <stream-slug> [--confirm] [--dry-run]

Two-step stream closure. Default run prints the harvest checklist so the
agent can distill this stream's contribution into project memory. Then
run again with --confirm to merge knowledge, remove the stream file and log closure.

Step 1 — harvest (no flag):
  Prints a checklist of what to extract from the stream and where to
  append it: gotchas.md, playbook.md, open-questions.md, decisions.md,
  learnings.md. The agent reads the checklist and writes those files
  itself using its Edit/Write tools.

Step 2 — finalize (--confirm):
  Merges the stream's '## Knowledge delta' into .platform/domains/<domain>.md
  (keyed facts are added, replaced or removed; cards are created if missing)
  Distills a summary line into .platform/knowledge/
  Copies the stream outside the repo (~/.agentboard/cold/<project>/closed/)
  and removes it from .platform/work/ — no archive folder accumulates
  Appends a closure row to .platform/memory/log.md
  Removes the stream row from work/ACTIVE.md

Knowledge delta (write it in the stream file while you work):
  ## Knowledge delta
  ### <domain-slug> | <layer>
  - [key] current-state fact (stamped with stream + date on merge)
  - [old-key] -                      a lone dash removes that fact

Flags:
  --confirm   Actually merge knowledge, close, remove. Run AFTER the harvest step.
  --dry-run   Preview the knowledge merge and closure without writing.

This is the compounding ritual: each close adds durable knowledge to the
project's memory files so the next agent inherits it via `ab brief`.
EOF
}

_close_print_harvest_prompt() {
  local slug="$1" stream_file="$2"
  local status
  status="$(frontmatter_value "$stream_file" "status")"

  printf '%s─── Harvest checklist for stream: %s%s%s%s ───%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$slug" "$C_BOLD" "$C_RESET"
  printf '%sStream file:%s %s  %s(status=%s)%s\n\n' \
    "$C_DIM" "$C_RESET" "$stream_file" "$C_DIM" "${status:-?}" "$C_RESET"

  cat <<EOF
Before --confirm, distill this stream's contribution into project memory.
For each category, append if applicable; skip if nothing to add.

${C_BOLD}0. KNOWLEDGE DELTA${C_RESET} — what is now true about the system that a future agent must know?
   File:   this stream file, section '## Knowledge delta'
   Format: ### <domain-slug> | <layer>      (layer: backend, web, mobile, ...)
           - [stable-key] current-state fact, with file paths in backticks
           - [old-key] -                    removes a fact that is no longer true
   Rule:   state the CURRENT truth, not what changed. --confirm merges these
           into .platform/domains/<domain>.md; same key replaces, new key adds.

${C_BOLD}1. GOTCHAS${C_RESET}  — any landmines discovered? (things that'll trip the next agent)
   File:   .platform/memory/gotchas.md
   Where:  between markers 'agentboard:gotchas:begin' and 'agentboard:gotchas:end'
   Format: 🔴 [domain/file] — one-line gotcha (date or incident ref)
           🔴 never-forget · 🟡 usually-matters · 🟢 minor

${C_BOLD}2. PLAYBOOK${C_RESET} — any shortcut, command, or ritual worth recording?
   File:   .platform/memory/playbook.md
   Where:  between markers 'agentboard:playbook:begin' and 'agentboard:playbook:end'
   Format: - **[area]** — practice (why/when)

${C_BOLD}3. OPEN QUESTIONS${C_RESET} — anything still unresolved?
   File:   .platform/memory/open-questions.md
   Add to: 'Active' section (between 'active:begin' / 'active:end' markers)
   Format: - $(today) — [domain] question (context)
   Also:   if this stream RESOLVED a prior Active question, move it to
           'Resolved' with: → answer (stream: ${slug})

${C_BOLD}4. DECISIONS${C_RESET} — locked-in architectural / product / tooling decisions?
   File:   .platform/memory/decisions.md
   Add row to the 'Locked decisions' table.

${C_BOLD}5. LEARNINGS${C_RESET} — non-obvious bug root-cause or hard-won pattern?
   File:   .platform/memory/learnings.md
   Add a new L-NNN block using the format at the top of that file.

When the harvest is done:
  1. Set  closure_approved: true  in ${stream_file}
  2. Run  ${C_BOLD}ab close ${slug} --confirm${C_RESET}

Step 1 is required — --confirm will refuse to run without it.
Skipping harvest is fine if the stream produced nothing durable — but once
the stream is closed its file is removed from the repo. The only knowledge
that survives is the delta and the memory files above.
EOF
  _close_print_domain_gap "$slug" "$stream_file"
  printf '\n'
}

_close_append_log() {
  local slug="$1" archive_path="$2" today_str="$3" agent="$4"
  local log="./.platform/memory/log.md"
  [[ -f "$log" ]] || return 0
  local line="${today_str} — closed stream ${slug} → ${archive_path} (by ${agent})"
  local tmp; tmp="$(mktemp)"
  awk -v new="$line" '
    BEGIN { inserted = 0 }
    /^---$/ && !inserted { print; print ""; print new; inserted = 1; next }
    { print }
    END { if (!inserted) { print ""; print new } }
  ' "$log" > "$tmp"
  mv "$tmp" "$log"
}

_close_update_active_registry_status() {
  local slug="$1"
  local registry="./.platform/work/ACTIVE.md"
  [[ -f "$registry" ]] || return 0
  local tmp; tmp="$(mktemp)"
  awk -F'|' -v slug="$slug" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function is_stream_row(s) {
      s = trim(s)
      return s == slug || s ~ ("\\[" slug "\\]\\(" slug "\\.md\\)")
    }
    {
      if (NF >= 5 && is_stream_row($2)) next
      print
    }
  ' "$registry" | awk '
    BEGIN { saw_stream = 0; inserted_none = 0 }
    /^\| [^|]+ \| [^|]+ \| [^|]+ \| [^|]+ \| [^|]+ \|$/ {
      if ($0 !~ /^\| Stream \| Type \| Status \| Agent \| Last updated \|$/) saw_stream = 1
    }
    /^---$/ && !saw_stream && !inserted_none {
      print "_(none)_"
      inserted_none = 1
    }
    { print }
  ' > "$tmp"
  mv "$tmp" "$registry"
}
