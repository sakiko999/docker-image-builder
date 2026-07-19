#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

run_capture() {
  local output_file=$1
  local status
  shift

  if "$@" >"$output_file" 2>&1; then
    return 0
  else
    status=$?
  fi

  return "$status"
}

temporary_directory=$(mktemp -d)
cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

output="$temporary_directory/output"

assert_status "local build rejects no target" 1 \
  run_capture "$output" bash "$ROOT/scripts/build-local.sh"
assert_eq "no target usage" \
  "error: usage: build-local.sh <target-id>" \
  "$(<"$output")"

assert_status "local build rejects a historical tag argument" 1 \
  run_capture "$output" bash "$ROOT/scripts/build-local.sh" nanobot v0.2.2
assert_eq "too many arguments usage" \
  "error: usage: build-local.sh <target-id>" \
  "$(<"$output")"

mkdir "$temporary_directory/bin"
docker_marker="$temporary_directory/docker-called"
printf '#!/usr/bin/env bash\nprintf docker > %q\nexit 77\n' "$docker_marker" > "$temporary_directory/bin/docker"
chmod +x "$temporary_directory/bin/docker"

assert_status "invalid target is rejected before Docker" 1 \
  run_capture "$output" env PATH="$temporary_directory/bin:$PATH" bash "$ROOT/scripts/build-local.sh" ../nanobot
assert_eq "invalid target error" \
  "error: invalid target id: ../nanobot" \
  "$(<"$output")"
if [[ -e "$docker_marker" ]]; then
  fail "invalid target validation invoked Docker"
fi

assert_status "target build rejects unknown option before network" 1 \
  run_capture "$output" bash "$ROOT/scripts/build-target.sh" --unexpected
assert_eq "unknown option error" \
  "error: usage: build-target.sh [--publish] <target-id>" \
  "$(<"$output")"

assert_status "target build rejects extra arguments before network" 1 \
  run_capture "$output" bash "$ROOT/scripts/build-target.sh" nanobot v0.2.2
assert_eq "target extra argument error" \
  "error: usage: build-target.sh [--publish] <target-id>" \
  "$(<"$output")"

assert_status "target build accepts --publish before validating its target" 1 \
  run_capture "$output" env PATH="$temporary_directory/bin:$PATH" bash "$ROOT/scripts/build-target.sh" --publish ../nanobot
assert_eq "publish target validation error" \
  "error: invalid target id: ../nanobot" \
  "$(<"$output")"
if [[ -e "$docker_marker" ]]; then
  fail "publish target validation invoked Docker"
fi

pass "local build command contract"
