# Reusable WirdSchonSoftware DMG style

**[Deutsch](README.md)**

If these documentation translations unintentionally differ in substance, the German version takes precedence.

The DMG creation process is based on the WSS distribution workflow used across projects.

- `wss-layout.json`: fixed shared WSS layout parameters. 640 × 480 pt background, light installation area at the top, black branding area at the bottom, 240-pt WSS logo, gray arrow, 80-pt icons. No cards or additional installation text.
- `app-dmg.json`: app name, bundle identifier, project/scheme, expected version/build/minimum OS version, path to the existing AppIcon within the app, volume name and DMG filename.
- `render-dmg-background.swift`: renders the separate background from these settings; `WSS_Logo.png` remains unchanged.
- `configure-dmg.py`: Finder window and icon positions from the same template. `Programme` is a link to `/Applications`.
- `set-dmg-icon.swift`: assigns the existing AppIcon to the DMG file. `.VolumeIcon.icns` inside the DMG is an exact copy of the compiled AppIcon; the volume's custom icon flag is set. No second icon design.

## Rebuilding

Requirements: macOS, Xcode and Python 3.10 or later with `venv`/`pip`; internet access for the version-pinned build tools `ds-store 1.3.3` and `mac-alias 2.2.3`. These are installed in isolation in `/private/tmp` and are not distributed. Apple's Python 3.9 is not sufficient for this; if necessary, set `PYTHON` to an already installed newer interpreter.

```sh
bash Distribution/build-dmg.sh
```

Optional: `PYTHON=/pfad/zu/python3`. Move any existing output beforehand; the script does not overwrite it. Without `APP_PATH`, the script builds only the committed app sources exported using `git archive HEAD`, creating a fresh Universal Release archive.

Xcode signs the Release archive ad hoc (`CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY=-`), incorporating the entitlements defined in the project. The script does not disable signing and does not re-sign the app afterwards. `verify-app.py` checks both architectures, including sandboxing and read-only access to user-selected files, version, minimum OS version, languages and AppIcon. This check runs before packaging and again directly inside the completed DMG mounted read-only. Missing entitlements cause the process to abort; this also applies when `APP_PATH` is supplied.

For other WSS apps or later versions, change only the app-specific configuration and retain the shared layout file. An existing Release app bundle can be supplied explicitly:

```sh
APP_PATH=/pfad/zur/Release-App.app APP_CONFIG=/pfad/app-dmg.json OUTPUT=/pfad/App-1.0.dmg bash Distribution/build-dmg.sh
```

`LAYOUT_CONFIG` can also be set. `DMG-Commit.txt` records the commit when building a fresh archive; when `APP_PATH` is supplied, its provenance must be established separately. The checksum is stored alongside the DMG. Temporary builds/archives/tools are never included in the DMG.

## Signing and Gatekeeper

The published app is **ad-hoc signed**. It is **neither signed with an Apple Developer ID nor notarized by Apple**. macOS/Gatekeeper may therefore block the first launch after downloading it.

After a blocked launch, the user can explicitly allow the app under **System Settings → Privacy & Security → Open Anyway**. Only do this if you trust the source of the app. [More information from Apple](https://support.apple.com/de-de/102445).

The current free, open-source hobby-project distribution deliberately does not use a paid Apple Developer account. This signing status is an intentional characteristic of the distribution and does not promise a future Developer ID-signed or notarized version.

User instructions for installation and first launch are available in the [German README](../README.md#installation-und-erster-start) and in the [English README](../README.en.md#installation-and-first-launch).

The volume icon is part of the DMG. The additional Finder icon of the outer DMG file is stored in macOS file metadata and may be lost during a transfer without metadata; the volume icon inside remains intact.
