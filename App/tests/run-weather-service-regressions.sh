#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_binary="${TMPDIR:-/tmp}/iw-weather-service-regressions-$$"
trap 'rm -f "$test_binary"' EXIT

/usr/bin/clang \
  -fobjc-arc \
  -Wall \
  -Wextra \
  -framework Foundation \
  "$source_dir/tests/weather-service-regressions.m" \
  -o "$test_binary"

"$test_binary"
