#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "publication workflow exists" 0 test -f "$ROOT/.github/workflows/build-images.yml"
assert_status "test workflow exists" 0 test -f "$ROOT/.github/workflows/test.yml"
workflow="$(cat "$ROOT/.github/workflows/build-images.yml")"
tests_workflow="$(cat "$ROOT/.github/workflows/test.yml")"

assert_contains "publication workflow is scheduled" "$workflow" "0 */6 * * *"
assert_contains "publication workflow is manually dispatchable" "$workflow" "workflow_dispatch:"
assert_contains "publication workflow can push state" "$workflow" "contents: write"
assert_contains "publication workflow can publish packages" "$workflow" "packages: write"
# Accept GITHUB_TOKEN or GHCR_PAT (user-level packages require PAT)
if echo "$workflow" | grep -q "GITHUB_TOKEN\|GHCR_PAT"; then
  : # ok
else
  fail "publication workflow should reference GITHUB_TOKEN or GHCR_PAT"
fi
assert_contains "test workflow runs script tests" "$tests_workflow" "tests/run.sh"
pass "workflow contract"
