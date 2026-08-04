#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

assert_status "Dockerfile exists" 0 test -f "$ROOT/targets/cli-proxy-api/Dockerfile"
assert_status "entrypoint exists" 0 test -f "$ROOT/targets/cli-proxy-api/entrypoint.sh"
assert_status "healthcheck exists" 0 test -f "$ROOT/targets/cli-proxy-api/healthcheck.sh"
dockerfile="$(cat "$ROOT/targets/cli-proxy-api/Dockerfile")"
entrypoint="$(cat "$ROOT/targets/cli-proxy-api/entrypoint.sh")"
healthcheck="$(cat "$ROOT/targets/cli-proxy-api/healthcheck.sh")"

assert_contains "Dockerfile accepts a base image" "$dockerfile" "ARG BASE_IMAGE"
assert_contains "Dockerfile pins HOME to /root" "$dockerfile" "ENV HOME=/root"
assert_contains "Dockerfile exposes proxy port" "$dockerfile" "EXPOSE 8317"
assert_contains "Dockerfile sets healthcheck" "$dockerfile" "cli-proxy-api-healthcheck"
assert_contains "Dockerfile sets entrypoint" "$dockerfile" "cli-proxy-api-overlay-entrypoint"
assert_contains "entrypoint bootstraps config from example" "$entrypoint" "config.example.yaml"
assert_contains "entrypoint copies config" "$entrypoint" "cp"
assert_contains "entrypoint execs the binary" "$entrypoint" "exec /CLIProxyAPI/CLIProxyAPI"
assert_contains "healthcheck probes /healthz" "$healthcheck" "/healthz"
assert_contains "healthcheck uses curl" "$healthcheck" "curl"
assert_status "target assets validate" 0 "$ROOT/scripts/validate-target.sh" cli-proxy-api
pass "cli-proxy-api image contract"
