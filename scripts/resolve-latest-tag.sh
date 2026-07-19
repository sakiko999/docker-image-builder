#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if (( $# != 1 )); then
  die "usage: $(basename "$0") <target-id>"
fi

require_command git
require_command jq
target_id=$1
"$SCRIPT_DIR/validate-target.sh" "$target_id" >/dev/null

repository=$(target_field "$target_id" '.upstream.repository')
pattern=$(target_field "$target_id" '.upstream.tagPattern')
refs_file=$(mktemp)
cleanup() {
  rm -f "$refs_file"
}
trap cleanup EXIT

git ls-remote --tags --refs "https://github.com/${repository}.git" > "$refs_file"
select_latest_tag_from_file "$refs_file" "$pattern"
