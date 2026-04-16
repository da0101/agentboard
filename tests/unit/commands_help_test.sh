#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_help_and_version_commands() {
  local dir output
  dir="$(mktemp -d)"

  run_cli_capture output "$dir" help
  assert_contains "$output" "agentboard — shared work-state for multi-provider AI workflows"
  assert_contains "$output" "install [--dir ...]"
  assert_contains "$output" "brief-upgrade [slug]"
  assert_contains "$output" "progress <stream-slug>"

  run_cli_capture output "$dir" version
  assert_contains "$output" "agentboard $VERSION"
}

test_help_and_version_commands
