#!/bin/zsh
set -euo pipefail

project_root=${0:a:h:h}
test_output=$(mktemp -d "${TMPDIR:-/tmp}/scroll-reverser-zoom-tests.XXXXXX")
trap 'rm -rf "$test_output"' EXIT

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
/usr/bin/clang \
  -isysroot "$sdk_path" \
  -mmacosx-version-min=13.5 \
  -fobjc-arc \
  -Wall \
  -Wextra \
  -Werror \
  -framework Foundation \
  -framework ApplicationServices \
  -framework Carbon \
  "$project_root/ModifierScrollZoom.m" \
  "$project_root/tests/ModifierScrollZoomTests.m" \
  -o "$test_output/ModifierScrollZoomTests"

"$test_output/ModifierScrollZoomTests"
