#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

temporary_root=$(mktemp -d)
source_directory="$temporary_root/source"
patch_directory="$temporary_root/patches"
empty_patch_directory="$temporary_root/empty-patches"

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$source_directory" "$patch_directory" "$empty_patch_directory"
printf 'one\n' > "$source_directory/message.txt"

cat > "$patch_directory/10-first.patch" <<'PATCH'
diff --git a/message.txt b/message.txt
index 5626abf..f719efd 100644
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-one
+two
PATCH

cat > "$patch_directory/20-second.patch" <<'PATCH'
diff --git a/message.txt b/message.txt
index f719efd..2bdf67a 100644
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-two
+three
PATCH

assert_status "applies patches in deterministic order" 0 "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$source_directory"
assert_eq "patches produce final content" "three" "$(<"$source_directory/message.txt")"

printf 'unchanged\n' > "$source_directory/message.txt"
assert_status "empty patch directory succeeds" 0 "$ROOT/scripts/apply-patches.sh" "$empty_patch_directory" "$source_directory"
assert_eq "empty patch directory leaves source unchanged" "unchanged" "$(<"$source_directory/message.txt")"

cat > "$patch_directory/30-bad.patch" <<'PATCH'
this is not a patch
PATCH

printf 'one\n' > "$source_directory/message.txt"
assert_status "invalid patch fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$source_directory"

pass "patch application"
