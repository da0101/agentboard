#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# ---------------------------------------------------------------------------
# File-size ratchet
#
# Hard rule: bash source files in bin/ and lib/ stay under MAX_LINES lines.
# Legacy files already over the cap are frozen at the size recorded below —
# they may shrink, but any growth fails this test. New files must never be
# added to the allowlist; split them instead.
# ---------------------------------------------------------------------------

MAX_LINES=300

# Format: "<path relative to repo root> <recorded line count>", one per line.
# Shrinking a file below its recorded count is fine (updating the count is
# optional but encouraged). Growing past the recorded count is a failure.
RATCHET_ALLOWLIST="
lib/agentboard/commands/checkpoint.sh 475
lib/agentboard/commands/doctor.sh 452
lib/agentboard/core/bootstrap_domains.sh 413
lib/agentboard/commands/update.sh 350
lib/agentboard/commands/init.sh 348
lib/agentboard/core/bootstrap_repos.sh 341
lib/agentboard/commands/events.sh 339
lib/agentboard/commands/install_hooks.sh 305
"

# Prints the recorded line count for the relative path in $1, or nothing
# if the file is not on the allowlist.
allowlisted_limit() {
  local rel="$1" entry path count
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry% *}"
    count="${entry##* }"
    if [ "$path" = "$rel" ]; then
      printf '%s' "$count"
      return 0
    fi
  done <<EOF
$RATCHET_ALLOWLIST
EOF
  return 0
}

# Every bash file the rule covers: *.sh under bin/ and lib/, plus the two
# extensionless entry points bin/agentboard and bin/ab.
list_bash_files() {
  find "$TEST_ROOT/bin" "$TEST_ROOT/lib" -type f -name '*.sh' 2>/dev/null | sort
  if [ -f "$TEST_ROOT/bin/agentboard" ]; then
    printf '%s\n' "$TEST_ROOT/bin/agentboard"
  fi
  if [ -f "$TEST_ROOT/bin/ab" ]; then
    printf '%s\n' "$TEST_ROOT/bin/ab"
  fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_ratchet_allowlist_entries_are_well_formed() {
  local entry path count
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry% *}"
    count="${entry##* }"
    [ -f "$TEST_ROOT/$path" ] \
      || fail "ratchet allowlist names a missing file: $path (remove the stale entry)"
    case "$count" in
      ''|*[!0-9]*) fail "ratchet allowlist entry has a non-numeric count: $entry" ;;
    esac
    [ "$count" -gt "$MAX_LINES" ] \
      || fail "ratchet allowlist entry is already under the $MAX_LINES-line cap: $entry (remove it)"
  done <<EOF
$RATCHET_ALLOWLIST
EOF
}

test_bash_files_respect_size_ratchet() {
  local violations="" f rel lines limit checked=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    checked=$(( checked + 1 ))
    rel="${f#$TEST_ROOT/}"
    lines="$(wc -l < "$f" | tr -d ' ')"
    limit="$(allowlisted_limit "$rel")"
    if [ -n "$limit" ]; then
      if [ "$lines" -gt "$limit" ]; then
        violations="$violations
  $rel: $lines lines, frozen at $limit (legacy file — shrink it, never grow it)"
      fi
    elif [ "$lines" -gt "$MAX_LINES" ]; then
      violations="$violations
  $rel: $lines lines, cap is $MAX_LINES (split the file; do not extend the allowlist)"
    fi
  done < <(list_bash_files)

  [ "$checked" -gt 0 ] || fail "ratchet found no bash files under bin/ and lib/"
  [ -z "$violations" ] || fail "file size ratchet violated:$violations"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_ratchet_allowlist_entries_are_well_formed
test_bash_files_respect_size_ratchet
