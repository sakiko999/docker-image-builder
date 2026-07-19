#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/scripts/lib/common.sh"

pattern='^v[0-9]+(\.[0-9]+)+(\.post[0-9]+)?$'
assert_eq "selects latest stable tag" "v0.2.2" "$(select_latest_tag_from_file "$ROOT/tests/fixtures/tags.txt" "$pattern")"

temporary_root=$(mktemp -d)
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

STATE_DIR="$temporary_root/state"
assert_status "missing state needs build" 0 state_needs_build nanobot v0.2.2 abc123

write_state \
  nanobot \
  HKUDS/nanobot \
  v0.2.2 \
  abc123 \
  ghcr.io/sakiko999/nanobot \
  overlay456 \
  2026-07-19T00:00:00Z

assert_status "state has expected schema" 0 jq -e '
  .schemaVersion == 1 and
  .target == "nanobot" and
  .upstream == { repository: "HKUDS/nanobot", tag: "v0.2.2", commit: "abc123" } and
  .image == { repository: "ghcr.io/sakiko999/nanobot", tags: ["latest", "v0.2.2"] } and
  .overlayCommit == "overlay456" and
  .builtAt == "2026-07-19T00:00:00Z"
' "$STATE_DIR/nanobot.json"
assert_status "matching tag and commit skips build" 1 state_needs_build nanobot v0.2.2 abc123
assert_status "changed tag needs build" 0 state_needs_build nanobot v0.2.3 abc123
assert_status "changed commit needs build" 0 state_needs_build nanobot v0.2.2 def456

pass "tag resolution and state"
