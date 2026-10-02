#!/bin/sh
set -eu
# Usage: sh Tests/run-localization-tests.sh /path/to/the/built/JahreszeitenTracker.app
# Resource lookup is tested against the actual compiled bundle, never the source JSON alone.
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_bundle=$1
check_dir=$(mktemp -d /private/tmp/FT2LocalizationCheck.XXXXXX)
xcrun swift -module-cache-path "$check_dir/bundle-modules" "$repo_dir/Tests/BundleLocalizationTests.swift" "$app_bundle"
check_app="$check_dir/LocalizationCheck.app"
mkdir -p "$check_app/Contents/MacOS"
ln -s "$app_bundle/Contents/Resources" "$check_app/Contents/Resources"
cp "$app_bundle/Contents/Info.plist" "$check_app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string LocalizationCheck "$check_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string test.JahreszeitenTracker.LocalizationCheck "$check_app/Contents/Info.plist"
cat "$repo_dir/JahreszeitenTracker/ContentView.swift" "$repo_dir/Tests/LocalizationTests.swift" > "$check_dir/LocalizedViews.swift"
xcrun swiftc -parse-as-library -module-cache-path "$check_dir/modules" \
  "$repo_dir/JahreszeitenTracker/TrackerCore.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveParser.swift" \
  "$repo_dir/JahreszeitenTracker/FT2FarmMetadata.swift" \
  "$repo_dir/JahreszeitenTracker/FarmCatalog.swift" \
  "$repo_dir/JahreszeitenTracker/FT2SaveAccess.swift" \
  "$repo_dir/JahreszeitenTracker/FarmManager.swift" \
  "$repo_dir/JahreszeitenTracker/FarmCardView.swift" \
  "$repo_dir/JahreszeitenTracker/SettingsView.swift" \
  "$check_dir/LocalizedViews.swift" -o "$check_app/Contents/MacOS/LocalizationCheck"
"$check_app/Contents/MacOS/LocalizationCheck" de "$repo_dir/JahreszeitenTracker/Localizable.xcstrings" "$check_dir/previews" -AppleLanguages '(de)' -AppleLocale de_DE
"$check_app/Contents/MacOS/LocalizationCheck" en "$repo_dir/JahreszeitenTracker/Localizable.xcstrings" "$check_dir/previews" -AppleLanguages '(en)' -AppleLocale en_US
"$check_app/Contents/MacOS/LocalizationCheck" de "$repo_dir/JahreszeitenTracker/Localizable.xcstrings" "$check_dir/fallback-previews" -AppleLanguages '(fr)' -AppleLocale fr_FR
printf 'UI previews: %s\n' "$check_dir/previews"
