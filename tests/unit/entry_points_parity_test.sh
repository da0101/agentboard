#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

# bin/ab and bin/agentboard are separate files. They drifted once (ab lacked
# distill/index/synthesize, so `ab close` silently skipped distilling). They
# must source the same modules and dispatch the same commands.

_sourced() { grep '^source' "$1" | sed 's/.*agentboard\///' | sort; }
_dispatch() { grep -E '^[[:space:]]+[a-z-]+\)[[:space:]]+cmd_' "$1" | awk '{print $1, $2}' | sort; }

test_entry_points_source_the_same_modules() {
  local diff_out
  diff_out="$(diff <(_sourced "$TEST_ROOT/bin/ab") <(_sourced "$TEST_ROOT/bin/agentboard") || true)"
  [[ -z "$diff_out" ]] || fail "bin/ab and bin/agentboard source different modules:
$diff_out"
}

test_entry_points_dispatch_the_same_commands() {
  local diff_out
  diff_out="$(diff <(_dispatch "$TEST_ROOT/bin/ab") <(_dispatch "$TEST_ROOT/bin/agentboard") || true)"
  [[ -z "$diff_out" ]] || fail "bin/ab and bin/agentboard dispatch different commands:
$diff_out"
}

test_entry_points_source_the_same_modules
test_entry_points_dispatch_the_same_commands
