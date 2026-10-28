# -----------------------------------------------------------------------------
# close_knowledge.sh — merge a stream's "## Knowledge delta" into domain cards.
#
# A stream records durable facts while the agent works:
#
#   ## Knowledge delta
#   ### questionnaires | backend
#   - [score-bands] Overlap rejected in `ScoreColour.clean()`; stable error codes
#   - [old-endpoint] -                      <- a lone dash removes that fact
#
# `ab close --confirm` upserts each keyed fact into .platform/domains/<domain>.md
# under the "## <layer>" section whose heading contains <layer> (created when
# missing, as is the card). Facts are stamped "(slug, date)". Cards therefore
# hold current state, never history. Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

CK_ADDED=0; CK_REPLACED=0; CK_REMOVED=0; CK_MISSING=0; CK_CARDS_NEW=0; CK_SKIPPED=0

# _ck_records <stream-file> — prints "domain|layer|key|text" per delta bullet
_ck_records() {
  awk '
    /^## Knowledge delta/ { on=1; next }
    on && /^## /          { on=0 }
    !on                   { next }
    # A heading still holding <placeholders> is the untouched template: ignore it.
    /^### /               { h=$0; sub(/^### */,"",h); skip=(h ~ /[<>]/); n=split(h, p, /[ ]*\|[ ]*/); d=p[1]; l=(n>1?p[2]:""); next }
    skip                  { next }
    /^- \[[A-Za-z0-9._-]+\] / {
      line=$0; sub(/^- \[/,"",line); k=line; sub(/\].*/,"",k)
      t=line; sub(/^[^]]*\] */,"",t)
      print d "|" l "|" k "|" t
    }' "$1"
}

_ck_title_case() { printf '%s' "$1" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1'; }

# _ck_new_card <file> <domain> <layer>
_ck_new_card() {
  local file="$1" domain="$2" day; day="$(today)"
  cat > "$file" <<EOF
---
domain_id: dom-${domain}
slug: ${domain}
status: active
repo_ids: []
related_domain_slugs: []
created_at: ${day}
updated_at: ${day}
---

# Domain: $(_ck_title_case "$domain")
EOF
}

# _ck_upsert <card> <layer> <key> <line|""> — rewrites card in place; line ""
# deletes. Sets CK_RESULT to added|replaced|removed|missing.
_ck_upsert() {
  local card="$1" layer="$2" key="$3" newline="$4" tmp res exists
  tmp="$(mktemp)"; res="$(mktemp)"
  # Pre-pass: does the key already live in ANY section matching the layer?
  exists="$(CK_LAYER="$layer" CK_KEY="$key" awk '
    BEGIN { lay=tolower(ENVIRON["CK_LAYER"]); p="- [" ENVIRON["CK_KEY"] "]" }
    /^## / { insec = (index(tolower($0), lay) > 0); next }
    insec && (index($0, p " ") == 1 || $0 == p) { print 1; exit }' "$card")"
  # Values go through ENVIRON, not -v: awk -v would interpret backslashes in facts.
  CK_LAYER="$layer" CK_KEY="$key" CK_NL="$newline" CK_RF="$res" CK_EXISTS="$exists" awk '
    function add_here() { if (!done && nl != "" && !exists) { print nl; done=1; r="added" } }
    function flush_blank() { for (i=0;i<blank;i++) print ""; blank=0 }
    BEGIN { layer=ENVIRON["CK_LAYER"]; key=ENVIRON["CK_KEY"]; nl=ENVIRON["CK_NL"]; rf=ENVIRON["CK_RF"]; exists=ENVIRON["CK_EXISTS"]
            prefix = "- [" key "]"; lay = tolower(layer) }
    # A key is replaced/removed in ANY section matching the layer; a new key is
    # added only to the FIRST matching section, so a fact never exists twice.
    /^## / {
      if (insec) { if (addsec) add_here(); flush_blank(); insec=0; addsec=0 }
      if (index(tolower($0), lay) > 0) {
        insec=1
        if (!found) { found=1; addsec=1 }
      }
      print; next
    }
    insec && NF == 0 { blank++; next }
    insec && index($0, prefix " ") == 1 || insec && $0 == prefix {
      flush_blank()
      if (!done) { if (nl != "") { print nl; r="replaced" } else r="removed"; done=1 }
      next
    }
    { flush_blank(); print }
    END {
      if (insec) { if (addsec) add_here(); flush_blank() }
      if (!found && nl != "") {
        print ""; print "## " toupper(substr(layer,1,1)) substr(layer,2); print nl; r="added"
      }
      if (r == "") r="missing"
      print r > rf
    }' "$card" > "$tmp"
  CK_RESULT="$(cat "$res")"
  mv "$tmp" "$card"
  rm -f "$res"
}

# _ck_apply <slug> <stream-file> <stage-dir> — merges every delta record into
# staged copies of the cards (originals untouched). Prints one line per change.
_ck_apply() {
  local slug="$1" stream="$2" stage="$3" day rec domain layer key text card staged line
  day="$(today)"
  CK_ADDED=0; CK_REPLACED=0; CK_REMOVED=0; CK_MISSING=0; CK_CARDS_NEW=0; CK_SKIPPED=0
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    IFS='|' read -r domain layer key text <<< "$rec"
    if [[ ! "$domain" =~ ^[a-z0-9][a-z0-9-]*$ || -z "$layer" ]]; then
      warn "knowledge delta: skipped [$key] — heading must be '### <domain-slug> | <layer>'"
      CK_SKIPPED=$((CK_SKIPPED + 1)); continue
    fi
    card="./.platform/domains/${domain}.md"
    staged="$stage/${domain}.md"
    if [[ ! -f "$staged" ]]; then
      if [[ -f "$card" ]]; then
        cp "$card" "$staged"
      elif [[ "$text" == "-" ]]; then
        CK_MISSING=$((CK_MISSING + 1)); continue
      else
        _ck_new_card "$staged" "$domain"; CK_CARDS_NEW=$((CK_CARDS_NEW + 1))
        say "  + new card: ${domain}"
      fi
    fi
    if [[ "$text" == "-" ]]; then line=""; else line="- [${key}] ${text} (${slug}, ${day})"; fi
    _ck_upsert "$staged" "$layer" "$key" "$line"
    case "$CK_RESULT" in
      added)    CK_ADDED=$((CK_ADDED + 1));       say "  + ${domain}/${layer}: [${key}] added" ;;
      replaced) CK_REPLACED=$((CK_REPLACED + 1)); say "  ~ ${domain}/${layer}: [${key}] replaced" ;;
      removed)  CK_REMOVED=$((CK_REMOVED + 1));   say "  ! ${domain}/${layer}: [${key}] REMOVED" ;;
      *)        CK_MISSING=$((CK_MISSING + 1));   say "  ? ${domain}/${layer}: [${key}] not found, nothing removed" ;;
    esac
  done < <(_ck_records "$stream")
}

# _ck_commit <stage-dir> — copy staged cards over the originals, bump updated_at
_ck_commit() {
  local f name; mkdir -p ./.platform/domains
  for f in "$1"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    cp "$f" "./.platform/domains/${name}"
    replace_frontmatter_line "./.platform/domains/${name}" "updated_at" "$(today)"
  done
}

# _ck_cold_store <slug> <stream-file> — copy the finished stream outside the repo
# so removing it never loses anything. Prints the destination path.
_ck_cold_store() {
  local slug="$1" file="$2" root dir proj
  root="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}"
  proj="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  dir="${root}/${proj}/closed"
  mkdir -p "$dir"
  cp -p "$file" "${dir}/${slug}-$(today).md"
  printf '%s' "${dir}/${slug}-$(today).md"
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
    printf '%s   Add these to your Knowledge delta before running --confirm.%s\n' \
      "$C_DIM" "$C_RESET"
  fi
}

# _ck_cold_store_qa <slug> <cold-dir> — move the stream's QA artifacts out of the
# repo. Exact names only (a prefix glob would take another stream's files when
# slugs share a prefix). Prints how many items moved.
_ck_cold_store_qa() {
  local slug="$1" dest="$2" f n=0 sub
  for f in "./.platform/work/qa/${slug}-manual-qa.md" \
           "./.platform/work/qa/${slug}-execution-journal.md" \
           "./.platform/work/qa/evidence/${slug}" \
           "./.platform/work/qa/artifacts/${slug}"; do
    [[ -e "$f" ]] || continue
    sub="${f#./.platform/work/qa/}"
    mkdir -p "${dest}/$(dirname "$sub")"
    cp -pR "$f" "${dest}/${sub}" && rm -rf "$f"
    n=$((n + 1))
  done
  printf '%s' "$n"
}
