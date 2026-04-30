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

  local archive_dir="./.platform/work/archive"
  mkdir -p "$archive_dir"
  local archive_path="$archive_dir/${slug}.md"
  if [[ -e "$archive_path" ]]; then
    local n=2
    while [[ -e "$archive_dir/${slug}-${n}.md" ]]; do n=$((n + 1)); done
    archive_path="$archive_dir/${slug}-${n}.md"
  fi

  if (( dry_run )); then
    printf '%sWould archive%s %s → %s\n' "$C_BOLD" "$C_RESET" "$stream_file" "$archive_path"
    printf '%sWould update frontmatter:%s status=done, closure_approved=true\n' "$C_BOLD" "$C_RESET"
    printf '%sWould update ACTIVE.md:%s row status → closed\n' "$C_BOLD" "$C_RESET"
    printf '%sWould append closure row to .platform/memory/log.md%s\n' "$C_BOLD" "$C_RESET"
    return 0
  fi

  local today_str agent
  today_str="$(today)"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  replace_frontmatter_line "$stream_file" "status" "done"
  replace_frontmatter_line "$stream_file" "closure_approved" "true"
  replace_frontmatter_line "$stream_file" "updated_at" "$today_str"

  mv "$stream_file" "$archive_path"

  _close_append_log "$slug" "$archive_path" "$today_str" "$agent"
  _close_update_active_registry_status "$slug"

  ok "Stream ${C_BOLD}${slug}${C_RESET} closed and archived → ${C_CYAN}${archive_path}${C_RESET}"
  say "  ${C_DIM}If the harvest step (gotchas/playbook/questions) wasn't done before --confirm,${C_RESET}"
  say "  ${C_DIM}those insights are now lost from project memory. Re-run without --confirm to see the checklist.${C_RESET}"
}

_close_print_help() {
  cat <<'EOF'
Usage: ab close <stream-slug> [--confirm] [--dry-run]

Two-step stream closure. Default run prints the harvest checklist so the
agent can distill this stream's contribution into project memory. Then
run again with --confirm to archive the stream file and log closure.

Step 1 — harvest (no flag):
  Prints a checklist of what to extract from the stream and where to
  append it: gotchas.md, playbook.md, open-questions.md, decisions.md,
  learnings.md. The agent reads the checklist and writes those files
  itself using its Edit/Write tools.

Step 2 — finalize (--confirm):
  Moves the stream file to .platform/work/archive/<slug>.md
  Sets status=done, closure_approved=true
  Appends a closure row to .platform/memory/log.md
  Updates work/ACTIVE.md row status to "closed" (row kept for history)

Flags:
  --confirm   Actually archive + log. Run AFTER the harvest step.
  --dry-run   Preview archive actions without writing.

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
the stream is archived, its raw context is no longer in active memory. The
only knowledge that survives is what you distilled into the files above.
EOF
  _close_print_domain_gap "$slug" "$stream_file"
  printf '\n'
}

# Appended to the harvest checklist. Reads domain slugs from the stream file,
# collects files touched in stream commits, and lists any that aren't mentioned
# in the domain file text. Pure informational — no writes.
_close_print_domain_gap() {
  local slug="$1" stream_file="$2"
  local raw_domains
  raw_domains="$(frontmatter_value "$stream_file" "domain_slugs")"
  [[ -z "$raw_domains" || "$raw_domains" == "[]" ]] && return 0
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  local base_branch touched_files
  base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  if [[ -n "$base_branch" ]] && ! is_placeholder_value "$base_branch" \
      && git rev-parse --verify "$base_branch" >/dev/null 2>&1; then
    touched_files="$(git log --name-only --pretty=format: "${base_branch}..HEAD" 2>/dev/null \
      | awk 'NF' | sort -u || true)"
  else
    touched_files="$(git log --name-only --pretty=format: -20 2>/dev/null \
      | awk 'NF' | sort -u || true)"
  fi
  [[ -n "$touched_files" ]] || return 0

  local any_gap=0 ds df domain_text gap_lines fpath
  while IFS= read -r ds; do
    [[ -z "$ds" ]] && continue
    df="./.platform/domains/${ds}.md"
    [[ -f "$df" ]] || continue
    domain_text="$(< "$df")"
    gap_lines=""
    while IFS= read -r fpath; do
      [[ -z "$fpath" ]] && continue
      printf '%s' "$domain_text" | grep -qF "$fpath" 2>/dev/null && continue
      gap_lines="${gap_lines}   ${fpath}\n"
    done <<< "$touched_files"
    if [[ -n "$gap_lines" ]]; then
      if (( any_gap == 0 )); then
        printf '%s6. DOMAIN GAP%s  — touched files not mentioned in domain doc(s)\n' \
          "$C_BOLD" "$C_RESET"
        any_gap=1
      fi
      printf '   Domain: %s\n' "$df"
      printf '%b' "$gap_lines"
    fi
  done < <(inline_array_items "$raw_domains")

  if (( any_gap )); then
    printf '%s   Update the domain doc(s) above before running --confirm.%s\n' \
      "$C_DIM" "$C_RESET"
  fi
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
  awk -F'|' -v OFS='|' -v slug="$slug" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      if (NF >= 5 && trim($2) == slug) {
        $4 = " closed "
        print
      } else {
        print
      }
    }
  ' "$registry" > "$tmp"
  mv "$tmp" "$registry"
}
