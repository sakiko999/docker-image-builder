#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSERT_HELPER="$ROOT/tests/lib/assert.sh"

if [[ ! -f "$ASSERT_HELPER" ]]; then
  printf 'FAIL: assertion helper is missing\n' >&2
  exit 1
fi

# shellcheck source=lib/assert.sh
source "$ASSERT_HELPER"

assert_eq "matches nanobot strings" "nanobot" "nanobot"
assert_contains "finds image in builder name" "nanobot-image-builder" "image"
assert_status "accepts successful command" 0 bash -c 'exit 0'

pass "harness assertions"
