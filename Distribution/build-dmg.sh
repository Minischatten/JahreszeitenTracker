#!/bin/bash
set -euo pipefail
DIST=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$DIST/.." && pwd)
WORK=$(mktemp -d /private/tmp/WSS-DMG.XXXXXX)
PYTHON=${PYTHON:-python3}
"$PYTHON" -c 'import sys; sys.exit("DMG tools require Python 3.10 or newer; set PYTHON to a suitable interpreter." if sys.version_info < (3, 10) else 0)'
APP_CONFIG=${APP_CONFIG:-"$DIST/app-dmg.json"}
LAYOUT_CONFIG=${LAYOUT_CONFIG:-"$DIST/wss-layout.json"}
config() { "$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$APP_CONFIG" "$1"; }
APP_NAME=$(config appName)
VERSION=$(config version)
BUILD=$(config build)
MINIMUM=$(config minimumSystemVersion)
DMG_FILE=$(config dmgFile)
VOLUME_NAME=$(config volumeName)
OUTPUT=${OUTPUT:-"$DIST/$DMG_FILE"}
MOUNT="$WORK/mount"
[[ ! -e "$OUTPUT" ]] || { echo "Move existing output aside first: $OUTPUT" >&2; exit 1; }
mkdir -p "$WORK/source" "$WORK/stage/.background" "$MOUNT"
# Optional APP_PATH must point to an already archived Release app. Otherwise build HEAD freshly.
if [[ -z "${APP_PATH:-}" ]]; then
    git -C "$REPO" archive HEAD | tar -x -C "$WORK/source"
    git -C "$REPO" rev-parse HEAD > "$DIST/DMG-Commit.txt"
    xcodebuild -quiet -project "$WORK/source/$(config project)" -scheme "$(config scheme)" \
        -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$WORK/build" -archivePath "$WORK/Release.xcarchive" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- archive
    APP_PATH="$WORK/Release.xcarchive/Products/Applications/$APP_NAME.app"
fi
APP="$WORK/stage/$APP_NAME.app"
ditto "$APP_PATH" "$APP"
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist") == "$VERSION" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist") == "$BUILD" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist") == "$MINIMUM" ]]
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")
ARCHS=$(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]
[[ -f "$APP/Contents/Resources/de.lproj/Localizable.strings" && -f "$APP/Contents/Resources/en.lproj/Localizable.strings" ]]
ICON="$APP/$(config appIcon)"
[[ -f "$ICON" ]]
# Keep Xcode's signature, including its project-generated sandbox entitlements.
# Externally supplied APP_PATH bundles must meet the same requirements.
"$PYTHON" "$DIST/verify-app.py" "$APP" "$APP_CONFIG"
LINK_LABEL=$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["applicationsLabel"])' "$LAYOUT_CONFIG")
ln -s /Applications "$WORK/stage/$LINK_LABEL"
# The volume icon is an exact copy of the existing compiled app icon, not separate artwork.
cp "$ICON" "$WORK/stage/.VolumeIcon.icns"
xcrun swift -module-cache-path "$WORK/swift-modules" "$DIST/render-dmg-background.swift" \
    "$LAYOUT_CONFIG" "$APP_CONFIG" "$DIST/WSS_Logo.png" "$DIST/DMG-Background.png"
cp "$DIST/DMG-Background.png" "$WORK/stage/.background/DMG-Background.png"
"$PYTHON" -m venv "$WORK/tools"
"$WORK/tools/bin/python" -m pip install --quiet --disable-pip-version-check ds-store==1.3.3 mac-alias==2.2.3
hdiutil create -volname "$VOLUME_NAME" -fs HFS+ -srcfolder "$WORK/stage" -format UDRW "$WORK/layout.dmg"
hdiutil attach "$WORK/layout.dmg" -mountpoint "$MOUNT" -nobrowse
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
"$WORK/tools/bin/python" "$DIST/configure-dmg.py" "$MOUNT" "$LAYOUT_CONFIG" "$APP_CONFIG"
xcrun SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT"
trap - EXIT
hdiutil convert "$WORK/layout.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
xcrun swift -module-cache-path "$WORK/swift-modules" "$DIST/set-dmg-icon.swift" "$ICON" "$OUTPUT"
hdiutil verify "$OUTPUT"
# Verify the distributed bundle, not just the staging copy.
hdiutil attach "$OUTPUT" -mountpoint "$MOUNT" -readonly -nobrowse
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
"$PYTHON" "$DIST/verify-app.py" "$MOUNT/$APP_NAME.app" "$APP_CONFIG"
cmp "$MOUNT/.VolumeIcon.icns" "$MOUNT/$APP_NAME.app/$(config appIcon)"
[[ $(readlink "$MOUNT/$LINK_LABEL") == /Applications ]]
hdiutil detach "$MOUNT"
trap - EXIT
(cd "$(dirname "$OUTPUT")" && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
echo "DMG: $OUTPUT"
echo "Build artifacts (not distributed): $WORK"
