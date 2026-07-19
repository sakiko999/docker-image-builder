#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob
tests=("$ROOT"/tests/test_*.sh)

if (( ${#tests[@]} == 0 )); then
  printf 'FAIL: no tests found\n' >&2
  exit 1
fi

for test_file in "${tests[@]}"; do
  bash "$test_file"
done
