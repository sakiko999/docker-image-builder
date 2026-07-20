#!/usr/bin/env bash
set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$COMMON_DIR/../.." rev-parse --show-toplevel)"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/state}"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

valid_target_id() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

target_dir() {
  valid_target_id "$1" || return 1
  printf '%s/targets/%s\n' "$REPO_ROOT" "$1"
}

target_config() {
  local directory
  directory=$(target_dir "$1") || return 1
  printf '%s/target.json\n' "$directory"
}

target_field() {
  jq -er "$2" "$(target_config "$1")"
}

safe_target_file_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

state_file() {
  safe_target_file_name "$1" || return 1
  printf '%s/%s.json\n' "$STATE_DIR" "$1"
}

select_latest_tag_from_file() {
  local refs_file=$1
  local pattern=$2
  local latest_tag

  latest_tag=$(awk '{
    tag = $2
    sub(/^refs\/tags\//, "", tag)
    print tag
  }' "$refs_file" | { grep -E -- "$pattern" || true; } | LC_ALL=C sort -V | tail -n 1)

  [[ -n "$latest_tag" ]] || die "no tags matched pattern: $pattern"
  printf '%s\n' "$latest_tag"
}

state_needs_build() {
  local target=$1
  local repository=$2
  local tag=$3
  local commit=$4
  local image=$5
  local overlay_commit=$6
  local file

  file=$(state_file "$target") || return 0
  [[ -f "$file" ]] || return 0

  if jq -e \
    --arg target "$target" \
    --arg repository "$repository" \
    --arg tag "$tag" \
    --arg commit "$commit" \
    --arg image "$image" \
    --arg overlay_commit "$overlay_commit" '
    .schemaVersion == 1 and
    .target == $target and
    (.upstream | type == "object") and
    (.upstream.repository | type == "string") and
    (.upstream.tag | type == "string") and
    (.upstream.commit | type == "string") and
    (.image | type == "object") and
    (.image.repository | type == "string") and
    .image.tags == ["latest", $tag] and
    (.overlayCommit | type == "string") and
    (.builtAt | type == "string") and
    .upstream.repository == $repository and
    .upstream.tag == $tag and
    .upstream.commit == $commit and
    .image.repository == $image and
    .overlayCommit == $overlay_commit
  ' "$file" >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

write_state() {
  local target=$1
  local repository=$2
  local tag=$3
  local commit=$4
  local image=$5
  local overlay_commit=$6
  local built_at=$7
  local file
  local temporary_file

  file=$(state_file "$target") || die "invalid state target: $target"
  mkdir -p "$STATE_DIR" || return 1
  temporary_file=$(mktemp "$STATE_DIR/.${target}.XXXXXX") || return 1

  if ! jq -n \
    --arg target "$target" \
    --arg repository "$repository" \
    --arg tag "$tag" \
    --arg commit "$commit" \
    --arg image "$image" \
    --arg overlay_commit "$overlay_commit" \
    --arg built_at "$built_at" \
    '{
      schemaVersion: 1,
      target: $target,
      upstream: { repository: $repository, tag: $tag, commit: $commit },
      image: { repository: $image, tags: ["latest", $tag] },
      overlayCommit: $overlay_commit,
      builtAt: $built_at
    }' > "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi

  if ! mv "$temporary_file" "$file"; then
    rm -f "$temporary_file"
    return 1
  fi
}
