#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

temporary_root=$(mktemp -d)
backup_targets="$temporary_root/targets"

cleanup() {
  if [[ -e "$backup_targets" && ! -e "$ROOT/targets" ]]; then
    mv "$backup_targets" "$ROOT/targets"
  fi
  rmdir "$temporary_root" 2>/dev/null || true
}
trap cleanup EXIT

assert_status "nanobot target validates" 0 "$ROOT/scripts/validate-target.sh" nanobot
assert_status "absolute validator works outside the repository" 0 bash -c 'cd "$1"; "$2" nanobot' bash "$temporary_root" "$ROOT/scripts/validate-target.sh"
assert_status "path traversal target is rejected" 1 "$ROOT/scripts/validate-target.sh" ../nanobot
assert_status "target config rejects invalid target ids" 1 bash -c 'source "$1"; target_config ../nanobot' bash "$ROOT/scripts/lib/common.sh"
assert_status "target field rejects missing values" 1 bash -c 'source "$1"; target_field nanobot .missing' bash "$ROOT/scripts/lib/common.sh"
assert_status "target field rejects null values" 1 bash -c 'source "$1"; target_field nanobot '"'"'.missing // null'"'"'' bash "$ROOT/scripts/lib/common.sh"
assert_eq "all targets" "nanobot" "$("$ROOT/scripts/list-targets.sh" all)"
assert_eq "all targets has deterministic ordering" "nanobot" "$(LC_ALL=POSIX "$ROOT/scripts/list-targets.sh" all)"
assert_status "unknown target is rejected" 1 "$ROOT/scripts/list-targets.sh" unknown

mv "$ROOT/targets" "$backup_targets"
assert_status "missing targets directory is rejected" 1 "$ROOT/scripts/list-targets.sh" all
mv "$backup_targets" "$ROOT/targets"

pass "target validation"
