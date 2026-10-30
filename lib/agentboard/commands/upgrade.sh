# -----------------------------------------------------------------------------
# ab upgrade [--apply] — bring a project on older Agentboard to the current tooling and
# strip the pollution, in one pass. Preview by default (nothing is written, nothing moves).
#
#   0 safety     --apply first saves entry files, skills, hooks, domains and memory (not the
#                bulky stuff tidy already copies) to ~/.agentboard/cold/<project>/pre-upgrade-<date>.tgz
#   1 update     refresh tool-owned files (ab update; never touches knowledge files)
#   2 tidy       archive/, graphify/, session dumps, closed rows, unused skills -> cold store; kernel sync
#   3 entry      slim an old unmarked CLAUDE.md / AGENTS.md / GEMINI.md (ab entry adopt)
#   4 cards      fix moved card paths, prune bullets that are only a deleted path (ab recall --check --fix --prune)
#   5 index      write .platform/CARDS.md for colleagues whose agents run without ab
#   6 hooks      install git hooks that are missing (never overwrites someone else's; no --force)
# Then prints before/after numbers and what only a human can do (stale cards, rescan, skills).
# Every step runs isolated: one failing step is reported, the rest still run. Re-runnable. Pure bash 3.2.
# -----------------------------------------------------------------------------

# Each step runs in a subshell so a die inside cannot end the upgrade; output is capped at
# UP_MAX_LINES (the full report is one command away, named in the last line).
UP_MAX_LINES=28
_up_step() { # <title> <cmd...>
  local title="$1"; shift
  printf '\n%s▸ %s%s\n' "$C_BOLD" "$title" "$C_RESET"
  local rc=0
  ( "$@" ) 2>&1 | awk -v m="$UP_MAX_LINES" 'NR <= m { print "  " $0 } NR > m { n++ } END { if (n) printf "  … %d more line(s) — run the step on its own for the full report\n", n }' || rc="${PIPESTATUS[0]}"
  [[ "$rc" == 0 ]] || warn "  step '$title' reported a problem — continuing"
}

# _up_metrics — "entry-tokens|pollution-kb|skills|skill-tokens|stale-paths|cards"
_up_metrics() {
  local tok kb sk st cards
  tok="$(NO_COLOR=1 cmd_entry check 2>&1 | sed -n 's/.*Session start ≈ \([0-9]*\) tokens.*/\1/p' | awk 'NR==1')"
  local -a dumps=(); local f; for f in ./.platform/memory/session-*.md; do [[ -f "$f" ]] && dumps+=("$f"); done
  kb="$(_tidy_kb ./.platform/work/archive ./.platform/graphify "${dumps[@]+"${dumps[@]}"}")"
  sk="$(NO_COLOR=1 cmd_skill_list 2>&1 | sed -n 's/^ *\([0-9]*\) installed skill(s) ≈ \([0-9]*\) tokens.*/\1|\2/p')"
  _recall_stale_scan; st="$RECALL_STALE_PATHS"
  cards="$(_recall_cards | grep -c . || true)"
  printf '%s|%s|%s|%s|%s' "${tok:-?}" "${kb:-0}" "${sk:-?|?}" "$st" "$cards"
}

_up_index_preview() { cmd_recall --index --check || true; }   # "stale" is the expected answer on an old project

_up_backup() {
  local cold dest p
  cold="${AGENTBOARD_COLD_DIR:-$HOME/.agentboard/cold}/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  mkdir -p "$cold"; dest="$cold/pre-upgrade-$(today).tgz"
  local -a keep=(); for p in .platform CLAUDE.md AGENTS.md GEMINI.md .claude .agents .codex; do [[ -e "$p" ]] && keep+=("$p"); done
  tar -czf "$dest" --exclude='.platform/work/archive' --exclude='.platform/graphify' --exclude='.platform/memory/session-*.md' "${keep[@]}" 2>/dev/null
  ok "Saved ${dest/#$HOME/~}  ($(du -h "$dest" | cut -f1)). Restore: tar -xzf it in the project root. (Git history also has everything tracked.)"
}

cmd_upgrade() {
  local apply=0 before after mode
  while [[ $# -gt 0 ]]; do
    case "$1" in --apply) apply=1 ;; -h|--help) sed -n 2,19p "$AGENTBOARD_ROOT/lib/agentboard/commands/upgrade.sh" | sed 's/^# \{0,1\}//'; return 0 ;; *) die "Unknown flag for upgrade: $1" ;; esac; shift
  done
  [[ -d ./.platform ]] || die "No .platform/ found here. Run it in a project that has one (ab init creates it)."
  mode="$( (( apply )) && echo 'applying' || echo 'preview — add --apply to write' )"
  printf '\n%s%sab upgrade%s (%s) — %s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$mode" "$(pwd -P)"
  git rev-parse --git-dir >/dev/null 2>&1 || warn "Not a git repo: git cannot undo this. The pre-upgrade backup still applies."
  if (( apply )) && [[ -n "$(git status --porcelain 2>/dev/null | awk 'NR==1')" ]]; then
    warn "The working tree has uncommitted changes. Upgrade changes many files: commit or stash first, or use a branch, so the result is one reviewable commit."
  fi
  before="$(_up_metrics)"

  if (( apply )); then _up_step "0 safety backup" _up_backup; fi
  if (( apply )); then _up_step "1 update tool files" cmd_update; else _up_step "1 update tool files (dry run)" cmd_update --dry-run; fi
  if (( apply )); then _up_step "2 tidy" cmd_tidy --apply; else _up_step "2 tidy" cmd_tidy; fi
  if (( apply )); then _up_step "3 entry files" cmd_entry adopt --apply; else _up_step "3 entry files" cmd_entry adopt; fi
  if (( apply )); then _up_step "4 knowledge cards" cmd_recall --check --fix --prune --apply; else _up_step "4 knowledge cards" cmd_recall --check --fix --prune; fi
  if (( apply )); then _up_step "5 card index" cmd_recall --index; else _up_step "5 card index" _up_index_preview; fi
  if (( apply )); then _up_step "6 git hooks" cmd_install_hooks; else _up_step "6 git hooks (dry run)" cmd_install_hooks --dry-run; fi

  after="$(_up_metrics)"
  _up_report "$before" "$after" "$apply"
}

_up_report() { # <before> <after> <apply>
  local b="$1" a="$2" apply="$3" last
  printf '\n%s▸ Result%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-34s %12s %12s\n' "" "before" "after"
  printf '  %-34s %12s %12s\n' "session start (tokens)"        "$(echo "$b" | cut -d'|' -f1)" "$(echo "$a" | cut -d'|' -f1)"
  printf '  %-34s %12s %12s\n' "pollution in the repo (KB)"    "$(echo "$b" | cut -d'|' -f2)" "$(echo "$a" | cut -d'|' -f2)"
  printf '  %-34s %12s %12s\n' "installed skills"              "$(echo "$b" | cut -d'|' -f3)" "$(echo "$a" | cut -d'|' -f3)"
  printf '  %-34s %12s %12s\n' "skill tokens in every prompt"  "$(echo "$b" | cut -d'|' -f4)" "$(echo "$a" | cut -d'|' -f4)"
  printf '  %-34s %12s %12s\n' "stale card paths"              "$(echo "$b" | cut -d'|' -f5)" "$(echo "$a" | cut -d'|' -f5)"
  (( apply )) || printf '\n  Preview only: "after" equals "before". Run again with --apply, then review `git status` and commit.\n'
  printf '\n  %sOnly you can do:%s\n' "$C_BOLD" "$C_RESET"
  [[ "$(echo "$a" | cut -d'|' -f5)" != 0 ]] && printf '  - %s card path(s) still match no file: ab recall --check (fix the card, or --accept a deliberate mention)\n' "$(echo "$a" | cut -d'|' -f5)"
  last="$(NO_COLOR=1 cmd_rescan 2>&1 | sed -n 's/.*Last scan:[^0-9n]*\([0-9-]*\).*/\1/p' | awk 'NR==1')"
  printf '  - Knowledge is as old as its last scan (%s). If the code moved on: ab rescan, then follow .platform/RESCAN.md; ab recall --affected --since <date> lists the cards to look at.\n' "${last:-never}"
  if [[ -d ios && -d android && ! -d .claude/skills/ab-mobile-native ]]; then printf '  - Native iOS + Android project: ab skill install ab-mobile-native\n'; fi
  if [[ "$(echo "$a" | cut -d'|' -f1)" =~ ^[0-9]+$ ]] && (( $(echo "$a" | cut -d'|' -f1) > 2000 )); then
    printf '  - Session start is over the 2000-token budget. No tool can decide which project facts matter; the biggest sections of CLAUDE.md are:\n'
    awk '/agentboard:kernel:begin/ { exit } /^## / { if (h != "") print n "\t" h; h = substr($0, 4); n = 0 } { n += length($0) + 1 } END { if (h != "") print n "\t" h }' CLAUDE.md 2>/dev/null \
      | sort -rn | awk 'NR <= 3 { printf "      %5d B  %s\n", $1, $2 }'
    printf '    Move detail that is not needed every session into a domain card (ab recall --list), keep the one-line rule in the entry file.\n'
  fi
  return 0
}
