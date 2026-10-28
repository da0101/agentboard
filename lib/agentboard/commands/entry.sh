# -----------------------------------------------------------------------------
# ab entry — the always-loaded entry files (CLAUDE.md / AGENTS.md / GEMINI.md).
#
#   ab entry kernel [claude|codex|gemini]   print the kernel block (with markers)
#   ab entry sync [--dry-run]               refresh the kernel inside root files
#   ab entry check                          measure session-start tokens vs budget
#   ab entry build-templates                (kit maintainers) regenerate the kernel in templates/root/
#
# The kernel is the kit-controlled part: hard rules plus one-line triggers into
# `ab protocol`. It is generated from templates/platform/kernel/*.md and pasted
# verbatim, never paraphrased. Project facts stay outside the kernel markers.
# Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

ENTRY_KERNEL_BEGIN='<!-- agentboard:kernel:begin v=1 -->'
ENTRY_KERNEL_END='<!-- agentboard:kernel:end v=1 -->'
ENTRY_ROOT_END='<!-- agentboard:root-entry:end v=1 -->'
ENTRY_KERNEL_SLOT='@@KERNEL@@'   # build-time slot in templates/root/*.template
ENTRY_BUDGET_WARN=2000
ENTRY_BUDGET_FAIL=3000

entry_usage() {
  cat <<'EOF2'
Usage: ab entry kernel [claude|codex|gemini]   print the kernel block
       ab entry sync [--dry-run]               refresh the kernel in CLAUDE.md / AGENTS.md / GEMINI.md
       ab entry check                          session-start tokens vs budget (warn 2000, fail 3000)

sync only touches files that carry Agentboard markers: it replaces the kernel
block in place, or inserts it just before the root-entry end marker. Files
without markers are reported and left alone.
EOF2
}

_entry_provider_for() {
  case "$1" in CLAUDE.md) echo claude ;; AGENTS.md) echo codex ;; GEMINI.md) echo gemini ;; *) echo claude ;; esac
}

_entry_tokens() { printf '%s' "$(( ($(wc -c < "$1" | tr -d ' ') + 3) / 4 ))"; }

# _entry_kernel_block <provider> — kernel text wrapped in markers
_entry_kernel_block() {
  local provider="$1" dir="$TEMPLATES_PLATFORM/kernel"
  [[ -f "$dir/core.md" ]] || die "Kernel source missing: $dir/core.md"
  [[ -f "$dir/${provider}.md" ]] || die "Unknown provider '$provider' (claude, codex, gemini)."
  printf '%s\n' "$ENTRY_KERNEL_BEGIN"
  cat "$dir/core.md"
  printf '\n'
  cat "$dir/${provider}.md"
  printf '%s\n' "$ENTRY_KERNEL_END"
}

# _entry_apply <file> <block-file> — rewrite file with the block; prints
# replaced|inserted|skipped
_entry_apply() {
  local file="$1" blockfile="$2" tmp mode
  if grep -qF "$ENTRY_KERNEL_SLOT" "$file"; then mode=slot
  elif grep -qF "$ENTRY_KERNEL_BEGIN" "$file"; then mode=replace
  elif grep -qF "$ENTRY_ROOT_END" "$file"; then mode=insert
  else printf 'skipped'; return 0
  fi
  tmp="$(mktemp)"
  MODE="$mode" SLOT="$ENTRY_KERNEL_SLOT" BLOCK="$blockfile" KB="$ENTRY_KERNEL_BEGIN" KE="$ENTRY_KERNEL_END" RE="$ENTRY_ROOT_END" awk '
    function emit(  l) { while ((getline l < ENVIRON["BLOCK"]) > 0) print l; close(ENVIRON["BLOCK"]) }
    ENVIRON["MODE"] == "slot" { if ($0 == ENVIRON["SLOT"]) emit(); else print; next }
    ENVIRON["MODE"] == "replace" {
      if (index($0, ENVIRON["KB"])) { skipping=1; emit(); next }
      if (skipping) { if (index($0, ENVIRON["KE"])) skipping=0; next }
      print; next
    }
    { if (index($0, ENVIRON["RE"]) && !done) { print ""; emit(); done=1 } print }' "$file" > "$tmp"
  mv "$tmp" "$file"
  case "$mode" in replace|slot) printf 'replaced' ;; *) printf 'inserted' ;; esac
}

cmd_entry_sync() {
  local dry=0 f name provider block result changed=0
  [[ "${1:-}" == "--dry-run" ]] && dry=1
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    f="./$name"
    [[ -f "$f" ]] || continue
    provider="$(_entry_provider_for "$name")"
    block="$(mktemp)"; _entry_kernel_block "$provider" > "$block"
    if (( dry )); then
      if grep -qF "$ENTRY_KERNEL_BEGIN" "$f"; then result="would replace"
      elif grep -qF "$ENTRY_ROOT_END" "$f"; then result="would insert"
      else result="skipped"; fi
    else
      result="$(_entry_apply "$f" "$block")"
    fi
    rm -f "$block"
    if [[ "$result" == skipped ]]; then
      warn "$name: no Agentboard markers — left alone (see: ab entry check)"
    else
      ok "$name: kernel $result"; changed=$((changed + 1))
    fi
  done
  (( changed > 0 )) || say "  No marker-managed entry files found."
}

# _entry_budget_eval — sets ENTRY_START (start packet tokens), ENTRY_WORST (largest
# entry file tokens), ENTRY_TOTAL and ENTRY_STATUS (OK|WARN|FAIL).
_entry_budget_eval() {
  local name f tok start_file
  ENTRY_WORST=0; ENTRY_STATUS="OK"
  start_file="$(mktemp)"
  cmd_brief_start > "$start_file" 2>/dev/null || true
  ENTRY_START="$(_entry_tokens "$start_file")"; rm -f "$start_file"
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    f="./$name"; [[ -f "$f" ]] || continue
    tok="$(_entry_tokens "$f")"
    if (( tok > ENTRY_WORST )); then ENTRY_WORST="$tok"; fi
  done
  ENTRY_TOTAL=$((ENTRY_WORST + ENTRY_START))
  if (( ENTRY_TOTAL > ENTRY_BUDGET_FAIL )); then ENTRY_STATUS="FAIL"
  elif (( ENTRY_TOTAL > ENTRY_BUDGET_WARN )); then ENTRY_STATUS="WARN"; fi
}

cmd_entry_check() {
  local name f has_kernel
  _entry_budget_eval
  printf '  %s%-14s %8s %8s  %s%s\n' "$C_DIM" "FILE" "BYTES" "~TOK" "KERNEL" "$C_RESET"
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    f="./$name"; [[ -f "$f" ]] || continue
    if grep -qF "$ENTRY_KERNEL_BEGIN" "$f"; then has_kernel="yes"; else has_kernel="no"; fi
    printf '  %-14s %8s %8s  %s\n' "$name" "$(wc -c < "$f" | tr -d ' ')" "$(_entry_tokens "$f")" "$has_kernel"
  done
  printf '  %-14s %8s %8s\n' "brief --start" "—" "$ENTRY_START"
  printf '\n  Session start ≈ %d tokens (largest entry file + start packet) — %s (warn %d / fail %d)\n' \
    "$ENTRY_TOTAL" "$ENTRY_STATUS" "$ENTRY_BUDGET_WARN" "$ENTRY_BUDGET_FAIL"
  if [[ "$ENTRY_STATUS" != OK ]]; then
    dim "  Trim project facts in the entry file, or move detail into domain cards (ab recall)."
  fi
  [[ "$ENTRY_STATUS" != FAIL ]]
}

# Kit maintenance: regenerate the kernel block inside templates/root/*.template
# from templates/platform/kernel/*.md (slot on first build, markers afterwards).
cmd_entry_build_templates() {
  local f provider block result root="${TEMPLATES_ROOT:-$AGENTBOARD_ROOT/templates/root}"
  for f in "$root"/*.md.template "$root"/*.md.hub.template; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in AGENTS*) provider=codex ;; GEMINI*) provider=gemini ;; *) provider=claude ;; esac
    block="$(mktemp)"; _entry_kernel_block "$provider" > "$block"
    result="$(_entry_apply "$f" "$block")"; rm -f "$block"
    ok "$(basename "$f"): kernel $result ($provider)"
  done
}

cmd_entry() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    kernel) _entry_kernel_block "${1:-claude}" ;;
    build-templates) cmd_entry_build_templates ;;
    sync)   [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."; cmd_entry_sync "$@" ;;
    check)  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."; cmd_entry_check ;;
    -h|--help|"") entry_usage ;;
    *) die "Unknown entry subcommand: $sub (kernel, sync, check)" ;;
  esac
}
