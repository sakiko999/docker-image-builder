#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  printf 'error: expected <patch-directory> <source-directory>\n' >&2
  exit 1
fi

patch_directory=$1
source_directory=$2

if [[ ! -d "$patch_directory" ]]; then
  printf 'error: patch directory does not exist or is not a directory: %s\n' "$patch_directory" >&2
  exit 1
fi

if [[ ! -d "$source_directory" ]]; then
  printf 'error: source directory does not exist or is not a directory: %s\n' "$source_directory" >&2
  exit 1
fi

export LC_ALL=C
shopt -s nullglob
patch_files=("$patch_directory"/*.patch)

for patch_file in "${patch_files[@]}"; do
  printf 'Applying patch: %s\n' "${patch_file##*/}"
  patch -d "$source_directory" -p1 < "$patch_file" || exit 1
done
