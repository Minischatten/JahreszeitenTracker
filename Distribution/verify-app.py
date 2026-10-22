#!/usr/bin/env python3
"""Check the actual universal app signature and distribution resources."""
import json
import pathlib
import plistlib
import re
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(app, config):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == config["bundleIdentifier"], "Unexpected bundle identifier")
    for key, expected in (("CFBundleShortVersionString", config["version"]),
                          ("CFBundleVersion", config["build"]),
                          ("LSMinimumSystemVersion", config["minimumSystemVersion"])):
        require(info.get(key) == expected, f"Unexpected {key}: {info.get(key)}")
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = run("lipo", "-archs", str(executable)).decode().split()
    require(set(architectures) == {"arm64", "x86_64"}, "Universal architectures missing")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    for architecture in architectures:
        signature = subprocess.check_output(
            ["codesign", "--display", "--verbose=4", "--arch", architecture, str(app)],
            stderr=subprocess.STDOUT).decode()
        require(re.findall(r"^Identifier=(.+)$", signature, re.MULTILINE) == [config["bundleIdentifier"]],
                f"Unexpected signing identifier ({architecture})")
        raw = run("codesign", "--display", "--arch", architecture,
                  "--entitlements", "-", "--xml", str(app))
        require(bool(raw.strip()), f"No embedded entitlements ({architecture})")
        entitlements = plistlib.loads(raw)
        for key in ("com.apple.security.app-sandbox",
                    "com.apple.security.files.user-selected.read-only"):
            require(entitlements.get(key) is True, f"Missing {key} ({architecture})")
        require(not entitlements.get("com.apple.security.files.user-selected.read-write"),
                f"Unexpected read-write entitlement ({architecture})")
        load_commands = run("otool", "-arch", architecture, "-l", str(executable)).decode()
        require(re.findall(r"\bminos\s+(\S+)", load_commands) == [config["minimumSystemVersion"]],
                f"Unexpected Mach-O minimum ({architecture})")
        print(f"Verified {architecture}: sandbox=true, user-selected.read-only=true")
    for language in ("de", "en"):
        require((app / f"Contents/Resources/{language}.lproj/Localizable.strings").is_file(),
                f"Missing localization: {language}")
    require((app / config["appIcon"]).is_file(), "AppIcon missing")
    print(f"Verified app: {app} ({config['version']} / {config['build']})")


if __name__ == "__main__":
    try:
        verify(pathlib.Path(sys.argv[1]), json.loads(pathlib.Path(sys.argv[2]).read_text()))
    except (ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        sys.exit(f"Distribution validation failed: {error}")
