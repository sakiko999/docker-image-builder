#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if (( $# != 1 )); then
  die "usage: $(basename "$0") <all|target-id>"
fi

if [[ "$1" != all ]]; then
  "$SCRIPT_DIR/validate-target.sh" "$1"
  exit 0
fi

targets_root="$REPO_ROOT/targets"
[[ -d "$targets_root" && -r "$targets_root" ]] || die "targets directory is missing or unreadable"

target_ids=$(LC_ALL=C find "$targets_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)

if [[ -n "$target_ids" ]]; then
  while IFS= read -r target_id; do
    "$SCRIPT_DIR/validate-target.sh" "$target_id"
  done <<< "$target_ids"
fi
