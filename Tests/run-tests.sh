#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /private/tmp/FT2TrackerCompiler.XXXXXX)
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$repo_dir/JahreszeitenTracker/TrackerCore.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveParser.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveAccess.swift" \
  "$repo_dir/Tests/TrackerCoreTests.swift" -o "$test_dir/tests"
"$test_dir/tests" "$@"
