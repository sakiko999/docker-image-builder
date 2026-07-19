#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local message=$1
  local expected=$2
  local actual=$3

  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected <$expected>, got <$actual>"
  fi
}

assert_contains() {
  local message=$1
  local haystack=$2
  local needle=$3

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message: expected <$haystack> to contain <$needle>" ;;
  esac
}

assert_status() {
  local message=$1
  local expected_status=$2
  local actual_status
  local errexit_enabled=false

  shift 2

  case $- in
    *e*) errexit_enabled=true ;;
  esac

  set +e
  "$@"
  actual_status=$?
  if [[ "$errexit_enabled" == true ]]; then
    set -e
  fi

  if [[ "$expected_status" != "$actual_status" ]]; then
    fail "$message: expected status <$expected_status>, got <$actual_status>"
  fi
}

pass() {
  printf 'PASS: %s\n' "$1"
}
