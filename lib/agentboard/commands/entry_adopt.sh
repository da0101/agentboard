# -----------------------------------------------------------------------------
# ab entry adopt [--apply] [--keep TEXT]... [--drop TEXT]... — slim an entry file
# that predates the kernel (no Agentboard markers), e.g. a 13 KB activated CLAUDE.md.
#
# Splits the file at its "## " headings and sorts each section:
#   DROP  procedure the kernel / `ab protocol` now owns (Workflow, Session Start,
#         New Task Bootstrap, Manual QA, Closure, Subagent Dispatch, Skills, ...)
#   KEEP  everything else — project facts, constraints, routing tables. Anything
#         it cannot classify is KEPT; deleting knowledge is never the default.
# Sections from "Existing ... content" to the end are real user text preserved by
# activation: they stay verbatim, after the markers. --keep / --drop override the
# sort by heading text (case-insensitive substring). Preview by default; --apply
# backs the original up to the cold store, then writes
#   <root-entry markers> preamble + kept sections + kernel </markers> + preserved tail
# Pure bash 3.2 + awk.
# -----------------------------------------------------------------------------

# Generic protocol headings the kernel/protocols replace. A heading is dropped only
# when, after removing (parentheticals) and `code`, it IS one of these phrases —
# optionally followed by a dash subtitle ("Stream Closure — Human Approval").
# "Workflow for editing this repo" and "Clinical workflow engine" are project text.
ADOPT_DROP_PATTERNS="workflow|session start|new task bootstrap|new task|during work|manual qa plan rule|manual qa|audit and closure|audit|stream closure|closure|active work|session memory|subagent dispatch|subagent model assignment|subagent|skills available to you|skills available|skills|role activation|context handoff|reasoning annotation|delegating to a specialist|long session fallback|reference pack|reference pack|mandatory protocol|rescan trigger|rescan"

# _adopt_class <heading> <keeps> <drops> -> drop|keep   (--keep/--drop match anywhere in the heading)
_adopt_class() {
  local h k d
  h="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r k; do [[ -n "$k" && "$h" == *"$k"* ]] && { echo keep; return; }; done <<< "$2"
  while IFS= read -r d; do [[ -n "$d" && "$h" == *"$d"* ]] && { echo drop; return; }; done <<< "$3"
  local core; core="$(printf '%s' "$h" | sed 's/([^)]*)//g; s/`[^`]*`//g; s/[[:space:]]*$//')"
  if printf '%s' "$core" | grep -qE "^($ADOPT_DROP_PATTERNS)([[:space:]]*[—–-].*)?$"; then echo drop; else echo keep; fi
}

# _adopt_norm — lowercase, punctuation to spaces, collapsed
_adopt_norm() { tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g' | tr -s ' '; }

# _adopt_rules <section-file> <corpus-file> — never/must/always/do-not lines the
# kernel and protocols do not already say (matched on their first six words)
_adopt_rules() {
  local line key
  sed '1d' "$1" | grep -iE "(^|[^a-z])(never|must not|must|always|do not|don't)([^a-z]|$)" 2>/dev/null | while IFS= read -r line; do
    (( ${#line} >= 25 )) || continue
    key="$(printf '%s' "$line" | _adopt_norm | awk '{ for (i = 1; i <= NF && i <= 6; i++) printf "%s%s", $i, (i < 6 && i < NF ? " " : "") }')"
    [[ -n "$key" ]] && grep -qF -- "$key" "$2" && continue
    printf '%s\n' "$line"
  done || true
}

# _adopt_split <file> <dir> — dir/pre, dir/sec.N (first line = heading), dir/tail
_adopt_split() {
  mkdir -p "$2"
  awk -v d="$2" '
    function out() { return (tail ? d "/tail" : (n == 0 ? d "/pre" : d "/sec." n)) }
    /^## [Ee]xisting .*content/ && !tail { tail = 1 }
    /^## / && !tail { n++ }
    { f = out(); print >> f }' "$1"
  [[ -f "$2/pre" ]] || : > "$2/pre"
}

_adopt_one() {
  local file="$1" apply="$2" keeps="$3" drops="$4" work s h cls n=0 kept_b=0 drop_b=0 b out blockf cold
  work="$(mktemp -d)"; _adopt_split "$file" "$work"
  cat "$TEMPLATES_PLATFORM"/kernel/*.md "$TEMPLATES_PLATFORM"/protocols/*.md 2>/dev/null | _adopt_norm > "$work/corpus"
  : > "$work/rules"
  printf '  %s%s%s (%d bytes)\n' "$C_BOLD" "$file" "$C_RESET" "$(wc -c < "$file" | tr -d ' ')"
  : > "$work/kept"
  for s in $(ls "$work" | grep '^sec\.' | sort -t. -k2 -n); do
    h="$(head_line "$work/$s")"; cls="$(_adopt_class "$h" "$keeps" "$drops")"; b="$(wc -c < "$work/$s" | tr -d ' ')"
    n=$((n + 1))
    if [[ "$cls" == drop ]]; then drop_b=$((drop_b + b)); printf '    %-5s %6d B  %s\n' "DROP" "$b" "$h"; _adopt_rules "$work/$s" "$work/corpus" >> "$work/rules"
    else kept_b=$((kept_b + b)); printf '    %-5s %6d B  %s\n' "keep" "$b" "$h"; cat "$work/$s" >> "$work/kept"; fi
  done
  [[ -s "$work/tail" ]] && printf '    %-5s %6d B  %s\n' "tail" "$(wc -c < "$work/tail" | tr -d ' ')" "preserved user content (after the markers)"
  printf '    → ≈ %d tokens saved from this file\n' "$((drop_b / 4))"
  if [[ -s "$work/rules" ]]; then
    printf '    Rules in dropped sections that the kernel does not state (carried over, review them):\n'
    awk 'NR <= 12 { print "      · " substr($0, 1, 150) }' "$work/rules"
  fi
  printf '\n'
  if (( apply )); then
    cold="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")/adopt-$(today)"
    mkdir -p "$cold" && cp -p "$file" "$cold/$(basename "$file")"
    out="$work/new"; blockf="$work/block"
    { printf '%s\n' '<!-- agentboard:root-entry:begin v=1 -->'
      awk '{ a[NR] = $0 } END { n = NR; while (n > 0 && a[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print a[i] }' "$work/pre"
      printf '\n'; grep -v '^---[[:space:]]*$' "$work/kept" || true
      if [[ -s "$work/rules" ]]; then
        printf '## Carried-over rules\n\n_Kept from sections the kernel replaced (adopted %s). Delete any that no longer apply._\n\n' "$(today)"
        awk 'NR <= 12 { sub(/^[ \t]*[-*][ \t]*/, ""); print "- " $0 }' "$work/rules"; printf '\n'
      fi
      printf '%s\n' '<!-- agentboard:root-entry:end v=1 -->'
      if [[ -s "$work/tail" ]]; then printf '\n---\n\n'; cat "$work/tail"; fi
    } > "$out"
    case "$(basename "$file")" in AGENTS.md) _entry_kernel_block codex ;; GEMINI.md) _entry_kernel_block gemini ;; *) _entry_kernel_block claude ;; esac > "$blockf"
    _entry_apply "$out" "$blockf" >/dev/null
    mv "$out" "$file"
    ok "$file rewritten (original saved to $cold/$(basename "$file"))"
  fi
  rm -rf "$work"
}

head_line() { sed -n '1p' "$1" | sed 's/^## *//'; }

cmd_entry_adopt() {
  local apply=0 keeps="" drops="" f any=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      --keep) keeps="$keeps$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"$'\n'; shift 2 ;;
      --drop) drops="$drops$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"$'\n'; shift 2 ;;
      -h|--help) sed -n 2,18p "$AGENTBOARD_ROOT/lib/agentboard/commands/entry_adopt.sh" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) die "Unknown flag for entry adopt: $1" ;;
    esac
  done
  [[ -d ./.platform ]] || die "No .platform/ found. Run 'ab init' first."
  printf '\n%s%sab entry adopt%s %s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$( (( apply )) && echo '(applying)' || echo '(preview — add --apply to write)')"
  for f in CLAUDE.md AGENTS.md GEMINI.md; do
    [[ -f "./$f" ]] || continue
    if grep -qF 'agentboard:root-entry:begin' "./$f"; then say "  $f: already has Agentboard markers — use: ab entry sync"; continue; fi
    if grep -qF 'agentboard:kernel:begin' "./$f"; then say "  $f: already carries the kernel (a fresh stub) — activation wraps it; or use: ab entry sync"; continue; fi
    any=1; _adopt_one "./$f" "$apply" "$keeps" "$drops"
  done
  (( any )) || say "  Nothing to adopt."
  (( apply )) && { say "  Check the result: ab entry check · git diff"; }
  return 0
}
