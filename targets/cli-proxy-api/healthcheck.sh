#!/bin/sh
set -eu

health_url="${CLI_PROXY_API_HEALTH_URL:-http://127.0.0.1:8317/healthz}"

exec curl -fsS --max-time 3 "$health_url"
