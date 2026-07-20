#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "Dockerfile exists" 0 test -f "$ROOT/targets/nanobot/Dockerfile"
assert_status "entrypoint exists" 0 test -f "$ROOT/targets/nanobot/entrypoint.sh"
assert_status "healthcheck exists" 0 test -f "$ROOT/targets/nanobot/healthcheck.sh"
dockerfile="$(cat "$ROOT/targets/nanobot/Dockerfile")"
entrypoint="$(cat "$ROOT/targets/nanobot/entrypoint.sh")"
healthcheck="$(cat "$ROOT/targets/nanobot/healthcheck.sh")"

assert_contains "Dockerfile accepts a base image" "$dockerfile" "ARG BASE_IMAGE"
assert_contains "Dockerfile exposes gateway health port" "$dockerfile" "EXPOSE 18790"
assert_contains "Dockerfile exposes WebUI port" "$dockerfile" "EXPOSE 8765"
assert_contains "Dockerfile sets gateway default" "$dockerfile" 'CMD ["gateway"]'
assert_contains "entrypoint checks writable state" "$entrypoint" "not writable"
assert_contains "healthcheck probes endpoint" "$healthcheck" "/health"
assert_status "target assets validate" 0 "$ROOT/scripts/validate-target.sh" nanobot
pass "nanobot image contract"
