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

temporary_root=$(mktemp -d)
config="$ROOT/targets/nanobot/target.json"
config_backup="$temporary_root/target.json"
adapter="$ROOT/targets/nanobot/build.sh"
adapter_backup="$temporary_root/build.sh"
had_adapter=false

cp "$config" "$config_backup"
if [[ -e "$adapter" || -L "$adapter" ]]; then
  cp -a "$adapter" "$adapter_backup"
  had_adapter=true
fi

cleanup() {
  cp "$config_backup" "$config"
  rm -f "$adapter"
  if [[ "$had_adapter" == true ]]; then
    cp -a "$adapter_backup" "$adapter"
  fi
  rm -rf "$temporary_root"
}
trap cleanup EXIT

fake_bin="$temporary_root/bin"
mkdir "$fake_bin"
network_marker="$temporary_root/network-called"
docker_marker="$temporary_root/docker-called"
docker_log="$temporary_root/docker.log"
adapter_marker="$temporary_root/adapter-called"
output="$temporary_root/output"
state_directory="$temporary_root/state"
mkdir "$state_directory"

printf '#!/usr/bin/env bash\nset -euo pipefail\nrepository_root=%q\nnetwork_marker=%q\nif [[ "$1" == "-C" ]]; then\n  directory=$2\n  shift 2\n  if [[ "$1" == "rev-parse" && "$2" == "--show-toplevel" ]]; then\n    printf "%%s\\n" "$repository_root"\n    exit 0\n  fi\n  if [[ "$1" == "rev-parse" && "$2" == "HEAD" ]]; then\n    if [[ "$directory" == "$repository_root" ]]; then\n      printf "overlay-test-sha\\n"\n    else\n      printf "upstream-test-sha\\n"\n    fi\n    exit 0\n  fi\nfi\ncase "$1" in\n  ls-remote)\n    : > "$network_marker"\n    printf "0123456789012345678901234567890123456789\\trefs/tags/v0.2.2\\n"\n    ;;\n  clone)\n    destination="${@: -1}"\n    mkdir -p "$destination"\n    ;;\n  *)\n    exit 88\n    ;;\nesac\n' \
  "$ROOT" "$network_marker" > "$fake_bin/git"
chmod +x "$fake_bin/git"

printf '#!/usr/bin/env bash\nset -euo pipefail\nmarker=%q\nlog=%q\n: > "$marker"\nprintf "%%s\\n" "$*" >> "$log"\nexit 0\n' \
  "$docker_marker" "$docker_log" > "$fake_bin/docker"
chmod +x "$fake_bin/docker"

real_jq=$(command -v jq)
printf '#!/usr/bin/env bash\nset -euo pipefail\nreal_jq=%q\nif [[ "$1" == "-n" ]]; then\n  exit 1\nfi\nexec "$real_jq" "$@"\n' \
  "$real_jq" > "$fake_bin/jq"
chmod +x "$fake_bin/jq"

unsafe_config="$temporary_root/unsafe-target.json"
"$real_jq" --arg adapter '../../../../bin/true' '.build.adapter = $adapter' \
  "$config" > "$unsafe_config"
mv "$unsafe_config" "$config"

assert_status "unsafe adapter is rejected before Docker or network" 1 \
  run_capture "$output" env PATH="$fake_bin:$PATH" bash "$ROOT/scripts/build-target.sh" nanobot
assert_contains "unsafe adapter error" "$(<"$output")" "invalid target adapter file name: nanobot"
if [[ -e "$docker_marker" ]]; then
  fail "unsafe adapter validation invoked Docker"
fi
if [[ -e "$network_marker" ]]; then
  fail "unsafe adapter validation attempted network access"
fi

cp "$config_backup" "$config"
printf '%s\n' 'old state' > "$state_directory/nanobot.json"
state_snapshot="$temporary_root/state-before-build.json"
cp "$state_directory/nanobot.json" "$state_snapshot"
printf '#!/usr/bin/env bash\nset -euo pipefail\n: > "$ADAPTER_MARKER"\n' > "$adapter"
chmod +x "$adapter"

assert_status "published images report failed state persistence" 1 \
  run_capture "$output" env \
    PATH="$fake_bin:$PATH" \
    STATE_DIR="$state_directory" \
    ADAPTER_MARKER="$adapter_marker" \
    bash "$ROOT/scripts/build-target.sh" --publish nanobot
assert_contains "engine resolves the fake upstream tag and SHA" "$(<"$output")" \
  "Selected target nanobot at upstream tag v0.2.2 (upstream-test-sha)"
assert_status "temporary adapter runs before publication" 0 test -e "$adapter_marker"
assert_eq "both image tags are pushed before state persistence" \
  $'push ghcr.io/sakiko999/nanobot:latest\npush ghcr.io/sakiko999/nanobot:v0.2.2' \
  "$(<"$docker_log")"
assert_status "failed state persistence preserves old state" 0 \
  cmp -s "$state_snapshot" "$state_directory/nanobot.json"
assert_contains "state persistence failure explains publication status" "$(<"$output")" \
  "images were published but state recording failed for target nanobot tag v0.2.2; a later run may rebuild"
assert_status "failed state persistence removes its temporary artifact" 1 \
  bash -c 'compgen -G "$1/.nanobot.*" > /dev/null' bash "$state_directory"

pass "build target safety"
