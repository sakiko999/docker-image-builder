#!/usr/bin/env bash
set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$COMMON_DIR/../.." rev-parse --show-toplevel)"

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
