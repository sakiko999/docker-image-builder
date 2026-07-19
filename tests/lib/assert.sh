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

  if (( $# == 0 )); then
    fail "$message: expected a command"
  fi

  case $- in
    *e*) errexit_enabled=true ;;
  esac

  if "$@"; then
    actual_status=0
  else
    actual_status=$?
  fi

  if [[ "$errexit_enabled" == true ]]; then
    set -e
  else
    set +e
  fi

  if [[ "$expected_status" != "$actual_status" ]]; then
    fail "$message: expected status <$expected_status>, got <$actual_status>"
  fi
}

pass() {
  printf 'PASS: %s\n' "$1"
}
