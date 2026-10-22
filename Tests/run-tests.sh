#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /private/tmp/FT2TrackerCompiler.XXXXXX)
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$repo_dir/JahreszeitenTracker/TrackerCore.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveParser.swift" \
  "$repo_dir/JahreszeitenTracker/FT2FarmMetadata.swift" \
  "$repo_dir/JahreszeitenTracker/FarmCatalog.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveAccess.swift" \
  "$repo_dir/Tests/TrackerCoreTests.swift" -o "$test_dir/tests"
"$test_dir/tests" "$@"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$repo_dir/JahreszeitenTracker/TrackerCore.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveParser.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveAccess.swift" \
  "$repo_dir/JahreszeitenTracker/FT2FarmMetadata.swift" \
  "$repo_dir/JahreszeitenTracker/FarmCatalog.swift" \
  "$repo_dir/JahreszeitenTracker/FarmPresentationSession.swift" \
  "$repo_dir/JahreszeitenTracker/FarmManager.swift" \
  "$repo_dir/Tests/FarmManagerTests.swift" -o "$test_dir/manager-tests"
"$test_dir/manager-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$repo_dir/JahreszeitenTracker/TrackerCore.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveParser.swift" \
  "$repo_dir/JahreszeitenTracker/FT2FarmMetadata.swift" \
  "$repo_dir/JahreszeitenTracker/FarmCatalog.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveAccess.swift" \
  "$repo_dir/JahreszeitenTracker/FarmManager.swift" \
  "$repo_dir/JahreszeitenTracker/FarmPresentationSession.swift" \
  "$repo_dir/JahreszeitenTracker/SeasonReminder.swift" \
  "$repo_dir/JahreszeitenTracker/ReminderManager.swift" \
  "$repo_dir/JahreszeitenTracker/MacNotificationService.swift" \
  "$repo_dir/Tests/ReminderTests.swift" -o "$test_dir/reminder-tests"
"$test_dir/reminder-tests"
xcrun swift -module-cache-path "$test_dir/modules" "$repo_dir/Tests/LicenseTests.swift" "$repo_dir"
