#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/scripts/lib/common.sh"

pattern='^v[0-9]+(\.[0-9]+)+(\.post[0-9]+)?$'
assert_status "fixture uses full SHA-1 refs" 0 bash -c '
  grep -Eq "^[0-9a-f]{40}[[:space:]]+refs/tags/" "$1" &&
  [[ $(wc -l < "$1") -eq $(grep -Ec "^[0-9a-f]{40}[[:space:]]+refs/tags/" "$1") ]]
' bash "$ROOT/tests/fixtures/tags.txt"
assert_eq "selects latest stable tag" "v0.2.2" "$(select_latest_tag_from_file "$ROOT/tests/fixtures/tags.txt" "$pattern")"

temporary_root=$(mktemp -d)
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

STATE_DIR="$temporary_root/state"
target=nanobot
repository=HKUDS/nanobot
tag=v0.2.2
commit=abc123
image=ghcr.io/sakiko999/nanobot
overlay=overlay456

assert_status "missing state needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"

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
assert_status "matching publication identity skips build" 1 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"
assert_status "changed tag needs build" 0 \
  state_needs_build "$target" "$repository" v0.2.3 "$commit" "$image" "$overlay"
assert_status "changed commit needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" def456 "$image" "$overlay"
assert_status "changed upstream repository needs build" 0 \
  state_needs_build "$target" example/nanobot "$tag" "$commit" "$image" "$overlay"
assert_status "changed image repository needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" ghcr.io/example/nanobot "$overlay"
assert_status "changed overlay needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" changed-overlay

printf '%s\n' '{ "upstream": { "tag": "v0.2.2", "commit": "abc123" } }' > "$STATE_DIR/nanobot.json"
assert_status "partial state needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"
printf '%s\n' '{ malformed json' > "$STATE_DIR/nanobot.json"
assert_status "malformed state needs build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"
printf '%s\n' '{"schemaVersion":1,"target":"nanobot","upstream":{"repository":"HKUDS/nanobot","tag":"v0.2.2","commit":"abc123"},"image":{"repository":"ghcr.io/sakiko999/nanobot","tags":[]},"overlayCommit":"overlay456","builtAt":"2026-07-19T00:00:00Z"}' > "$STATE_DIR/nanobot.json"
assert_status "empty image tags need build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"
printf '%s\n' '{"schemaVersion":1,"target":"nanobot","upstream":{"repository":"HKUDS/nanobot","tag":"v0.2.2","commit":"abc123"},"image":{"repository":"ghcr.io/sakiko999/nanobot","tags":["latest",123]},"overlayCommit":"overlay456","builtAt":"2026-07-19T00:00:00Z"}' > "$STATE_DIR/nanobot.json"
assert_status "non-string image tags need build" 0 \
  state_needs_build "$target" "$repository" "$tag" "$commit" "$image" "$overlay"

write_state \
  nanobot \
  HKUDS/nanobot \
  v0.2.2 \
  abc123 \
  ghcr.io/sakiko999/nanobot \
  overlay456 \
  2026-07-19T00:00:00Z
assert_status "successful rewrite has expected schema" 0 jq -e '
  .schemaVersion == 1 and
  .target == "nanobot" and
  .upstream == { repository: "HKUDS/nanobot", tag: "v0.2.2", commit: "abc123" } and
  .image == { repository: "ghcr.io/sakiko999/nanobot", tags: ["latest", "v0.2.2"] } and
  .overlayCommit == "overlay456" and
  .builtAt == "2026-07-19T00:00:00Z"
' "$STATE_DIR/nanobot.json"

snapshot="$temporary_root/state-before-failed-write.json"
cp "$STATE_DIR/nanobot.json" "$snapshot"
fake_bin="$temporary_root/fake-bin"
mkdir "$fake_bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fake_bin/jq"
chmod +x "$fake_bin/jq"
original_path=$PATH
PATH="$fake_bin:$PATH"
if write_state nanobot HKUDS/nanobot v0.2.2 abc123 ghcr.io/sakiko999/nanobot overlay456 2026-07-19T00:00:00Z; then
  fail "failed jq serialization must make write_state fail"
fi
PATH=$original_path
assert_status "failed write preserves prior state" 0 cmp -s "$snapshot" "$STATE_DIR/nanobot.json"
assert_status "failed write removes temporary state" 1 bash -c 'compgen -G "$1/.nanobot.*" > /dev/null' bash "$STATE_DIR"

pass "tag resolution and state"
