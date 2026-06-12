#!/usr/bin/env bash
#
# Unit test runner.
#
# Usage: tests/unit.sh [--filter <pattern>] [--verbose]
#   --filter <pattern>  run only unit test files whose basename matches
#                       *<pattern>* (shell glob, no regex)
#   --verbose           print per-test pass/fail as each file runs
#
# Continues across failing files, names the failing test function, and
# exits 1 if anything failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILTER=""
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      if [[ $# -lt 2 ]]; then
        printf 'unit.sh: --filter requires a pattern\n' >&2
        exit 2
      fi
      FILTER="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      printf 'Usage: tests/unit.sh [--filter <pattern>] [--verbose]\n'
      exit 0
      ;;
    *)
      printf 'unit.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

WRAPPER="$(mktemp)"
MARKERS="$(mktemp)"
trap 'rm -f "$WRAPPER" "$MARKERS"' EXIT

# Sources one test file unmodified. A DEBUG trap watches FUNCNAME and
# writes the name of each test_* function to fd 3 the moment it starts,
# so the runner can count tests and name the failing one.
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
__AB_CURRENT=""
__ab_probe() {
  local i cur=""
  i=$(( ${#FUNCNAME[@]} - 1 ))
  while [ "$i" -ge 1 ]; do
    case "${FUNCNAME[$i]}" in
      test_*) cur="${FUNCNAME[$i]}"; break ;;
    esac
    i=$(( i - 1 ))
  done
  if [ -n "$cur" ] && [ "$cur" != "$__AB_CURRENT" ]; then
    __AB_CURRENT="$cur"
    { printf '%s\n' "$cur" >&3; } 2>/dev/null || true
  fi
  return 0
}
set -o functrace
trap '__ab_probe' DEBUG
source "$1"
EOF

FILES_RUN=0
TESTS_RUN=0
FAILED=0

for test_file in "$ROOT"/unit/*_test.sh; do
  base="$(basename "$test_file")"
  if [[ -n "$FILTER" ]]; then
    case "$base" in
      *${FILTER}*) ;;
      *) continue ;;
    esac
  fi
  FILES_RUN=$((FILES_RUN + 1))
  if [[ "$VERBOSE" -eq 1 ]]; then
    printf 'RUN: %s\n' "$base"
  fi

  : > "$MARKERS"
  set +e
  bash "$WRAPPER" "$test_file" 3>"$MARKERS"
  status=$?
  set -e

  file_tests="$(grep -c . "$MARKERS" || true)"
  failing_fn="$(awk 'NF { last = $0 } END { print last }' "$MARKERS")"
  TESTS_RUN=$((TESTS_RUN + file_tests))

  if [[ "$VERBOSE" -eq 1 ]]; then
    while IFS= read -r fn; do
      [[ -n "$fn" ]] || continue
      if [[ "$status" -ne 0 && "$fn" == "$failing_fn" ]]; then
        printf '  FAIL %s\n' "$fn"
      else
        printf '  ok %s\n' "$fn"
      fi
    done < "$MARKERS"
  fi

  if [[ "$status" -ne 0 ]]; then
    FAILED=$((FAILED + 1))
    if [[ -n "$failing_fn" ]]; then
      printf 'FAIL: %s -> %s\n' "$base" "$failing_fn" >&2
    else
      printf 'FAIL: %s -> (failed before first test function)\n' "$base" >&2
    fi
  fi
done

if [[ "$FILES_RUN" -eq 0 ]]; then
  printf 'unit.sh: no test files match filter: %s\n' "$FILTER" >&2
  exit 1
fi

if [[ "$FAILED" -gt 0 ]]; then
  printf 'FAIL: unit (%d of %d files failed, %d tests run)\n' \
    "$FAILED" "$FILES_RUN" "$TESTS_RUN" >&2
  exit 1
fi

printf 'PASS: unit (%d files, %d tests)\n' "$FILES_RUN" "$TESTS_RUN"
