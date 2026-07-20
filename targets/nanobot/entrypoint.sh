#!/bin/sh
set -eu

data_dir="$(printenv NANOBOT_HOME 2>/dev/null || true)"
if [ -z "$data_dir" ]; then
  data_dir="$HOME/.nanobot"
fi

if [ -d "$data_dir" ] && [ ! -w "$data_dir" ]; then
  printf 'Error: %s is not writable; mount a directory writable by the container user.\n' "$data_dir" >&2
  exit 1
fi

exec nanobot "$@"
