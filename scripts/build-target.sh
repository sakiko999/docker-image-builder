#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  die "usage: build-target.sh [--publish] <target-id>"
}

publish=false
case $# in
  1)
    target_id=$1
    [[ "$target_id" != --* ]] || usage
    ;;
  2)
    [[ "$1" == "--publish" ]] || usage
    publish=true
    target_id=$2
    ;;
  *)
    usage
    ;;
esac

valid_target_id "$target_id" || die "invalid target id: $target_id"

require_command git
require_command jq
"$SCRIPT_DIR/validate-target.sh" "$target_id" >/dev/null

target_directory=$(target_dir "$target_id")
repository=$(target_field "$target_id" '.upstream.repository')
image_repository=$(target_field "$target_id" '.image.repository')
adapter_name=$(target_field "$target_id" '.build.adapter')
safe_target_file_name "$adapter_name" || die "invalid target adapter file name: $target_id"
require_command docker
upstream_tag=$("$SCRIPT_DIR/resolve-latest-tag.sh" "$target_id")

source_directory=$(mktemp -d)
cleanup() {
  rm -rf "$source_directory"
}
trap cleanup EXIT

git clone --depth 1 --branch "$upstream_tag" --single-branch \
  "https://github.com/${repository}.git" "$source_directory"
upstream_sha=$(git -C "$source_directory" rev-parse HEAD)

printf 'Selected target %s at upstream tag %s (%s)\n' \
  "$target_id" "$upstream_tag" "$upstream_sha"

overlay_sha="$(git -C "$ROOT" rev-list -1 HEAD -- ':!state' 2>/dev/null || true)"
if [ -z "$overlay_sha" ]; then
  overlay_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo local)"
fi

if [[ "$publish" == true ]] && ! state_needs_build \
  "$target_id" "$repository" "$upstream_tag" "$upstream_sha" "$image_repository" "$overlay_sha"; then
  printf 'Skipping publish for %s: upstream tag %s (%s) is already current\n' \
    "$target_id" "$upstream_tag" "$upstream_sha"
  exit 0
fi

"$SCRIPT_DIR/apply-patches.sh" "$target_directory/patches" "$source_directory"

adapter="$target_directory/$adapter_name"
[[ -f "$adapter" && ! -L "$adapter" && -x "$adapter" ]] || die "adapter is not a regular executable: $adapter"

export REPO_ROOT="$ROOT"
export TARGET_DIR="$target_directory"
export SOURCE_DIR="$source_directory"
export UPSTREAM_TAG="$upstream_tag"
export UPSTREAM_SHA="$upstream_sha"
export IMAGE_REPOSITORY="$image_repository"
export IMAGE_TAG="$upstream_tag"
export OVERLAY_SHA="$overlay_sha"
"$adapter"

if [[ "$publish" == true ]]; then
  docker push "$image_repository:latest"
  docker push "$image_repository:$upstream_tag"
  if ! write_state "$target_id" "$repository" "$upstream_tag" "$upstream_sha" \
    "$image_repository" "$overlay_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
    printf 'error: images were published but state recording failed for target %s tag %s; a later run may rebuild\n' \
      "$target_id" "$upstream_tag" >&2
    exit 1
  fi
fi
