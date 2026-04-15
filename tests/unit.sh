#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_file in "$ROOT"/unit/*_test.sh; do
  bash "$test_file"
done

printf 'PASS: unit\n'
