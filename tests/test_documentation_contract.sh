#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "README exists" 0 test -f "$ROOT/README.md"
assert_status "target documentation exists" 0 test -f "$ROOT/docs/adding-target.md"
readme="$(cat "$ROOT/README.md")"
target_docs="$(cat "$ROOT/docs/adding-target.md")"

assert_contains "README names nanobot" "$readme" "HKUDS/nanobot"
assert_contains "README documents local build" "$readme" "./scripts/build-local.sh nanobot"
assert_contains "README documents GHCR tags" "$readme" ":latest"
assert_contains "target documentation names target JSON" "$target_docs" "target.json"
assert_contains "target documentation forbids source forks" "$target_docs" "must not commit upstream source"
pass "documentation contract"
