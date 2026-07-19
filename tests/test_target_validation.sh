#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "nanobot target validates" 0 "$ROOT/scripts/validate-target.sh" nanobot
assert_status "path traversal target is rejected" 1 "$ROOT/scripts/validate-target.sh" ../nanobot
assert_eq "all targets" "nanobot" "$("$ROOT/scripts/list-targets.sh" all)"
assert_status "unknown target is rejected" 1 "$ROOT/scripts/list-targets.sh" unknown

pass "target validation"
