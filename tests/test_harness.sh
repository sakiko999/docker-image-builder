#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSERT_HELPER="$ROOT/tests/lib/assert.sh"

if [[ ! -f "$ASSERT_HELPER" ]]; then
  printf 'FAIL: assertion helper is missing\n' >&2
  exit 1
fi

# shellcheck source=lib/assert.sh
source "$ASSERT_HELPER"

assert_eq "matches nanobot strings" "nanobot" "nanobot"
assert_contains "finds image in builder name" "nanobot-image-builder" "image"
assert_status "accepts successful command" 0 bash -c 'exit 0'

function_assertion_status=
function_assertion_output=
if function_assertion_output=$(bash -c '
  source "$1"
  set +e

  turns_on_errexit() {
    set -e
    return 7
  }

  assert_status "function status is accepted" 7 turns_on_errexit

  case $- in
    *e*)
      printf "FAIL: caller errexit is enabled after assertion\\n" >&2
      exit 1
      ;;
  esac
' bash "$ASSERT_HELPER" 2>&1); then
  function_assertion_status=0
else
  function_assertion_status=$?
fi
assert_eq "function status assertion succeeds" 0 "$function_assertion_status"
assert_eq "function status assertion is quiet" "" "$function_assertion_output"

missing_command_status=
missing_command_output=
if missing_command_output=$(bash -c '
  source "$1"
  set +e
  assert_status "missing command" 0
' bash "$ASSERT_HELPER" 2>&1); then
  missing_command_status=0
else
  missing_command_status=$?
fi
assert_eq "missing command assertion status" 1 "$missing_command_status"
assert_contains \
  "missing command assertion explains failure" \
  "$missing_command_output" \
  "FAIL: missing command: expected a command"

pass "harness assertions"
