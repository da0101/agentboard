#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cmd_distill — distill a closed stream into structured JSONL knowledge records.
#
# Usage: ab distill <slug> [--quiet] [--dry-run]
#
# Appends records to .platform/knowledge/{streams,learnings,decisions}.jsonl.
# Template-based extraction only — no API calls. Pure bash + awk/grep/sed.
# -----------------------------------------------------------------------------

# Escape a value for embedding in a JSON double-quoted string.
_json_string_escape() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Convert a YAML inline array "[a, b]" to a JSON array "["a","b"]".
_yaml_array_to_json() {
  local raw; raw="$(trim "$1")"
  [[ -z "$raw" || "$raw" == "[]" ]] && printf '[]' && return 0
  raw="${raw#\[}"; raw="${raw%\]}"
  local item out="" arr
  IFS=',' read -r -a arr <<< "$raw"
  for item in "${arr[@]}"; do
    item="$(trim "$item")"; [[ -z "$item" ]] && continue
    out="${out:+${out},}\"$(_json_string_escape "$item")\""
  done
  printf '[%s]' "$out"
}

# Ensure .platform/knowledge/ exists; print its path.
_distill_kdir() {
  local kdir="./.platform/knowledge"
  mkdir -p "$kdir"
  printf '%s' "$kdir"
}

# Append a JSONL line to a file.
_distill_append() { printf '%s\n' "$2" >> "$1"; }

# Stamp distilled_at into stream frontmatter (add if absent, replace if present).
_distill_stamp() {
  local file="$1" date="$2"
  if grep -q "^distilled_at:" "$file" 2>/dev/null; then
    replace_frontmatter_line "$file" "distilled_at" "$date"
    return
  fi
  local tmp; tmp="$(mktemp)"
  awk -v d="$date" '
    BEGIN { fm=0; done=0 }
    /^---[[:space:]]*$/ {
      fm++
      if (fm==2 && !done) { print "distilled_at: " d; done=1 }
      print; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Parse L-NNN blocks from learnings.md; append new ones to learnings.jsonl.
_distill_learnings() {
  local slug="$1" kdir="$2" quiet="$3"
  local src="./.platform/memory/learnings.md"
  [[ -f "$src" ]] || return 0
  local out="${kdir}/learnings.jsonl"
  local count=0
  local id="" title="" date="" domain="" body="" in_block=0

  _distill_flush_learning() {
    [[ -z "$id" ]] && return
    if [[ -f "$out" ]] && grep -qF "\"id\":\"${id}\"" "$out" 2>/dev/null; then
      id=""; return
    fi
    local eb et ed edom esl
    eb="$(_json_string_escape "$(trim "$body")")"
    et="$(_json_string_escape "$title")"
    ed="$(_json_string_escape "$date")"
    edom="$(_json_string_escape "$domain")"
    esl="$(_json_string_escape "$slug")"
    _distill_append "$out" \
      "{\"type\":\"learning\",\"id\":\"${id}\",\"date\":\"${ed}\",\"domain\":\"${edom}\",\"title\":\"${et}\",\"body\":\"${eb}\",\"stream_slug\":\"${esl}\",\"tags\":[]}"
    count=$((count + 1))
    id=""
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+(L-[0-9]+)[[:space:]]—[[:space:]](.+)$ ]]; then
      _distill_flush_learning
      id="${BASH_REMATCH[1]}"; title="$(trim "${BASH_REMATCH[2]}")"
      date=""; domain=""; body=""; in_block=1; continue
    fi
    (( in_block )) || continue
    if [[ "$line" =~ ^##[[:space:]] && ! "$line" =~ ^##[[:space:]]+L-[0-9]+ ]]; then
      in_block=0; continue
    fi
    [[ "$line" =~ ^Date:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]] && date="${BASH_REMATCH[1]}"
    [[ "$line" =~ \|[[:space:]]*Repo:[[:space:]]*(.+)$ ]] && domain="$(trim "${BASH_REMATCH[1]}")"
    body+="${line}"$'\n'
  done < "$src"
  _distill_flush_learning

  (( quiet || count == 0 )) || ok "  learnings: ${count} new L-block(s) → learnings.jsonl"
}

# Parse locked-decisions table from decisions.md; append new rows.
_distill_decisions() {
  local slug="$1" kdir="$2" quiet="$3"
  local src="./.platform/memory/decisions.md"
  [[ -f "$src" ]] || return 0
  local out="${kdir}/decisions.jsonl"
  local count=0 in_table=0

  while IFS= read -r line; do
    [[ "$line" =~ ^##[[:space:]]+Locked[[:space:]]decisions ]] && { in_table=1; continue; }
    (( in_table )) && [[ "$line" =~ ^##[[:space:]] ]] && { in_table=0; continue; }
    (( in_table )) || continue
    [[ "$line" =~ ^\|[[:space:]]*#[[:space:]]*\| ]] && continue  # header
    [[ "$line" =~ ^\|[-[:space:]|]+\|$ ]] && continue             # separator
    [[ "$line" =~ ^\| ]] || continue

    local date topic decision why alts
    date="$(printf '%s' "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    topic="$(printf '%s' "$line"    | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')"
    decision="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5); print $5}')"
    why="$(printf '%s' "$line"      | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')"
    alts="$(printf '%s' "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$7); print $7}')"

    [[ -z "$topic" ]] && continue

    # Dedup: skip if same date+topic already recorded
    local etopic; etopic="$(_json_string_escape "$topic")"
    if [[ -f "$out" ]] && grep -qF "\"topic\":\"${etopic}\"" "$out" 2>/dev/null; then
      local edate; edate="$(_json_string_escape "$date")"
      grep -qF "\"date\":\"${edate}\"" "$out" 2>/dev/null && continue
    fi

    local ed et edec ew ea esl
    ed="$(_json_string_escape "$date")"
    et="$etopic"
    edec="$(_json_string_escape "$decision")"
    ew="$(_json_string_escape "$why")"
    ea="$(_json_string_escape "$alts")"
    esl="$(_json_string_escape "$slug")"
    _distill_append "$out" \
      "{\"type\":\"decision\",\"date\":\"${ed}\",\"topic\":\"${et}\",\"decision\":\"${edec}\",\"why\":\"${ew}\",\"alternatives\":\"${ea}\",\"stream_slug\":\"${esl}\"}"
    count=$((count + 1))
  done < "$src"

  (( quiet || count == 0 )) || ok "  decisions: ${count} new row(s) → decisions.jsonl"
}

cmd_distill() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "$slug" == "-h" || "$slug" == "--help" ]]; then
    _distill_help; return 0
  fi
  shift

  local quiet=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--quiet)  quiet=1; shift ;;
      --dry-run)   dry_run=1; shift ;;
      -h|--help)   _distill_help; return 0 ;;
      *) die "Unknown flag: $1. Run 'ab distill --help'." ;;
    esac
  done

  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case: $slug"

  local stream_file=""
  local active_path="./.platform/work/${slug}.md"
  local archive_path="./.platform/work/archive/${slug}.md"
  if   [[ -f "$active_path" ]];  then stream_file="$active_path"
  elif [[ -f "$archive_path" ]]; then stream_file="$archive_path"
  else die "Stream file not found: ${active_path} or ${archive_path}"
  fi

  has_frontmatter "$stream_file" || \
    die "${stream_file} has no v1 frontmatter. Run 'ab migrate --apply' first."

  local kdir; kdir="$(_distill_kdir)"
  local streams_file="${kdir}/streams.jsonl"

  # Deduplication guard
  if [[ -f "$streams_file" ]] && grep -qF "\"slug\":\"${slug}\"" "$streams_file" 2>/dev/null; then
    (( quiet )) || warn "Already distilled: ${slug}. Skipping."
    return 0
  fi

  # Extract frontmatter
  local title status domain_slugs_raw base_branch updated_at agent
  title="$(frontmatter_value "$stream_file" "title")"
  [[ -z "$title" ]] && title="$slug"
  status="$(frontmatter_value "$stream_file" "status")"
  [[ -z "$status" ]] && status="done"
  domain_slugs_raw="$(frontmatter_value "$stream_file" "domain_slugs")"
  base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  updated_at="$(frontmatter_value "$stream_file" "updated_at")"
  agent="$(frontmatter_value "$stream_file" "agent_owner")"
  [[ -z "$agent" ]] && agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  local today_str; today_str="$(today)"
  local domain_slugs_json; domain_slugs_json="$(_yaml_array_to_json "$domain_slugs_raw")"

  # Extract summary: first non-blank body line after frontmatter, or first Scope bullet
  local summary
  summary="$(awk '
    BEGIN { fm=0; past=0 }
    /^---[[:space:]]*$/ { fm++; if (fm==2) past=1; next }
    !past || /^#/ { next }
    /^[[:space:]]*$/ { next }
    { print; exit }
  ' "$stream_file" | sed 's/^[- *`]*//; s/^[[:space:]]*//')"

  if (( dry_run )); then
    say "Would append to ${streams_file}:"
    say "  slug=${slug}  title=${title}  status=${status}  closed_at=${updated_at}"
    say "Would scan learnings.md and decisions.md for new records."
    return 0
  fi

  # Build and append stream record
  local es et estat eb ec ea esum
  es="$(_json_string_escape "$slug")"
  et="$(_json_string_escape "$title")"
  estat="$(_json_string_escape "$status")"
  eb="$(_json_string_escape "$base_branch")"
  ec="$(_json_string_escape "$updated_at")"
  ea="$(_json_string_escape "$agent")"
  esum="$(_json_string_escape "$summary")"

  _distill_append "$streams_file" \
    "{\"type\":\"stream\",\"slug\":\"${es}\",\"title\":\"${et}\",\"status\":\"${estat}\",\"domain_slugs\":${domain_slugs_json},\"base_branch\":\"${eb}\",\"closed_at\":\"${ec}\",\"agent\":\"${ea}\",\"summary\":\"${esum}\",\"tags\":${domain_slugs_json}}"

  _distill_learnings "$slug" "$kdir" "$quiet"
  _distill_decisions "$slug" "$kdir" "$quiet"
  _distill_stamp "$stream_file" "$today_str"

  (( quiet )) || ok "Distilled ${C_BOLD}${slug}${C_RESET} → ${C_CYAN}${kdir}/${C_RESET}"
}

_distill_help() {
  cat <<'EOF'
Usage: ab distill <stream-slug> [--quiet] [--dry-run]

Distills a closed stream file into structured JSONL knowledge records.
Reads from .platform/work/<slug>.md or .platform/work/archive/<slug>.md.

Appends to:
  .platform/knowledge/streams.jsonl     — stream metadata
  .platform/knowledge/learnings.jsonl   — L-NNN blocks from memory/learnings.md
  .platform/knowledge/decisions.jsonl   — locked decisions from memory/decisions.md

Idempotent: skips if slug already present in streams.jsonl.
Stamps distilled_at: <date> into the stream file frontmatter on success.

Flags:
  -q, --quiet   Suppress ok/info output; errors still print.
  --dry-run     Preview without writing.
  -h, --help    Show this help.

Called automatically by 'ab close <slug> --confirm' when agentboard is on PATH.
EOF
}
