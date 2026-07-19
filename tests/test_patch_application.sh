#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

temporary_root=$(mktemp -d)
source_directory="$temporary_root/source"
patch_directory="$temporary_root/patches"
empty_patch_directory="$temporary_root/empty-patches"
patch_output="$temporary_root/patch-output"

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$source_directory" "$patch_directory" "$empty_patch_directory"
printf 'one\n' > "$source_directory/message.txt"

assert_status "no arguments fail" 1 "$ROOT/scripts/apply-patches.sh"
assert_status "wrong argument count fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_directory"
assert_status "extra argument fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$source_directory" extra
assert_status "missing patch directory fails" 1 "$ROOT/scripts/apply-patches.sh" "$temporary_root/missing-patches" "$source_directory"
assert_status "missing source directory fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$temporary_root/missing-source"

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

mkdir "$patch_directory/ignored.patch"
mkdir "$patch_directory/nested"

cat > "$patch_directory/nested/50-nested.patch" <<'PATCH'
diff --git a/message.txt b/message.txt
index 2bdf67a..23c4f9d 100644
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-three
+nested
PATCH

assert_status "applies patches in deterministic order" 0 bash -o pipefail -c '"$1" "$2" "$3" 2>&1 | tee "$4"' bash "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$source_directory" "$patch_output"
assert_eq "patches produce final content" "three" "$(<"$source_directory/message.txt")"
assert_status "patch directories are not logged" 1 grep -F "Applying patch: ignored.patch" "$patch_output"
assert_status "nested patch is not logged" 1 grep -F "Applying patch: 50-nested.patch" "$patch_output"

printf 'unchanged\n' > "$source_directory/message.txt"
assert_status "empty patch directory succeeds" 0 "$ROOT/scripts/apply-patches.sh" "$empty_patch_directory" "$source_directory"
assert_eq "empty patch directory leaves source unchanged" "unchanged" "$(<"$source_directory/message.txt")"

cat > "$patch_directory/30-bad.patch" <<'PATCH'
this is not a patch
PATCH

cat > "$patch_directory/40-after.patch" <<'PATCH'
diff --git a/message.txt b/message.txt
index 2bdf67a..8518bdc 100644
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-three
+four
PATCH

printf 'one\n' > "$source_directory/message.txt"
assert_status "invalid patch fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_directory" "$source_directory"
assert_eq "invalid patch stops later patches" "three" "$(<"$source_directory/message.txt")"

pass "patch application"
