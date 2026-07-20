#!/bin/sh
set -eu

health_url="$(printenv NANOBOT_HEALTH_URL 2>/dev/null || true)"
if [ -z "$health_url" ]; then
  health_url="http://127.0.0.1:18790/health"
fi

exec python - "$health_url" <<'PY'
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    if response.status != 200:
        raise SystemExit("unexpected health status: %s" % response.status)
PY
