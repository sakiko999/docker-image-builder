#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if (( $# != 1 )); then
  die "usage: $(basename "$0") <target-id>"
fi

require_command jq
target_id=$1

valid_target_id "$target_id" || die "invalid target id: $target_id"
config=$(target_config "$target_id")
[[ -d "$(target_dir "$target_id")" ]] || die "target does not exist: $target_id"
[[ -f "$config" ]] || die "target configuration does not exist: $target_id"

jq -e '
  .schemaVersion == 1 and
  (.id | type == "string") and
  (.upstream.repository | type == "string") and
  (.upstream.tagPattern | type == "string") and
  (.image.repository | type == "string") and
  .image.platform == "linux/amd64" and
  (.build.adapter | type == "string") and
  (.build.dockerfile | type == "string")
' "$config" >/dev/null || die "invalid target configuration: $target_id"

[[ "$(target_field "$target_id" '.id')" == "$target_id" ]] || die "target id does not match directory: $target_id"
[[ "$(target_field "$target_id" '.image.repository')" == ghcr.io/* ]] || die "image repository must begin with ghcr.io/: $target_id"

adapter=$(target_field "$target_id" '.build.adapter')
dockerfile=$(target_field "$target_id" '.build.dockerfile')
safe_target_file_name "$adapter" || die "invalid target adapter file name: $target_id"
safe_target_file_name "$dockerfile" || die "invalid target Dockerfile name: $target_id"

printf '%s\n' "$target_id"
