#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "publication workflow exists" 0 test -f "$ROOT/.github/workflows/build-images.yml"
assert_status "test workflow exists" 0 test -f "$ROOT/.github/workflows/test.yml"
pass "workflow contract"
