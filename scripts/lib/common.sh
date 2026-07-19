#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

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
  printf '%s/target.json\n' "$(target_dir "$1")"
}

target_field() {
  jq -r "$2" "$(target_config "$1")"
}

safe_target_file_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}
