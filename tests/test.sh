#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$ROOT/unit.sh"
bash "$ROOT/integration.sh"

printf 'PASS: all-tests\n'
