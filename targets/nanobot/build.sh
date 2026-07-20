#!/usr/bin/env bash
set -euo pipefail

err() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

[ -n "$SOURCE_DIR" ] || err "SOURCE_DIR is not set"
[ -n "$TARGET_DIR" ] || err "TARGET_DIR is not set"
[ -n "$IMAGE_REPOSITORY" ] || err "IMAGE_REPOSITORY is not set"
[ -n "$IMAGE_TAG" ] || err "IMAGE_TAG is not set"
[ -n "$UPSTREAM_SHA" ] || err "UPSTREAM_SHA is not set"

platform="$(jq -er '.image.platform' "$TARGET_DIR/target.json")"
base_image="local/nanobot-upstream:$UPSTREAM_SHA"

docker build --platform "$platform" \
  --file "$SOURCE_DIR/Dockerfile" \
  --tag "$base_image" \
  "$SOURCE_DIR"

docker build --platform "$platform" \
  --file "$TARGET_DIR/Dockerfile" \
  --build-arg "BASE_IMAGE=$base_image" \
  --build-arg "UPSTREAM_TAG=$UPSTREAM_TAG" \
  --build-arg "UPSTREAM_SHA=$UPSTREAM_SHA" \
  --build-arg "OVERLAY_SHA=$OVERLAY_SHA" \
  --tag "$IMAGE_REPOSITORY:latest" \
  --tag "$IMAGE_REPOSITORY:$IMAGE_TAG" \
  "$REPO_ROOT"
