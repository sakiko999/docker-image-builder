#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if (( $# != 1 )); then
  printf 'error: usage: build-local.sh <target-id>\n' >&2
  exit 1
fi

exec "$SCRIPT_DIR/build-target.sh" "$1"
