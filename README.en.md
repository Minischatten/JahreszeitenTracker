# JahreszeitenTracker

**[Deutsche Version](README.md)**

If these README translations unintentionally differ in substance, the German version takes precedence. This does not affect the official GPL license text in `LICENSE`.

A free, open-source hobby project for **Farm Together 2** on macOS. JahreszeitenTracker displays the current season and the time remaining until the next season change.

## Features

- Automatic detection of multiple FT2 main farms and their existing plots.
- An overview and farm details with season images and a countdown; a custom card order and the option to hide farms.
- One-time season reminders delivered as local macOS notifications. Once scheduled, reminders can appear even after the app has quit, provided notifications are allowed.
- Automatic reading of new saves; valid last-known references remain in use if folder access is temporarily unavailable.
- German and English through the standard macOS language settings, without a custom language switch.

## Requirements and use

**macOS 14 Sonoma or later**, Apple Silicon or Intel. Release builds support both architectures (`arm64` and `x86_64`). Farm Together 2 is required separately and is not included.

Explicitly select the FT2 save folder in Settings. The tracker automatically detects the main farms within it. **FT2 saves are read only and are never modified.**

Currently confirmed FT2 save versions: **347, 350 and 352**. The intermediate versions 348, 349 and 351 are not confirmed. Newer, unknown versions are detected and checked conservatively. Data that cannot be read safely does not replace a valid reference; unconfirmed metadata is not an authoritative basis for removing known farms. A version number alone does not establish compatibility.

## Installation and first launch

1. Open the DMG and drag `JahreszeitenTracker.app` onto `Programme` (the Applications folder link).
2. Launch the app from Applications.
3. If macOS/Gatekeeper blocks the first launch, explicitly allow the app under **System Settings → Privacy & Security → Open Anyway**. Only do this if you trust the source of the app. [More information from Apple](https://support.apple.com/en-us/102445).
4. On the first successful launch, choose **Choose Save Folder…** in Settings and select the folder for your own Steam ID.

Usual location:

```text
~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/
```

`<Steam-ID>` represents your own Steam ID. Select that Steam ID folder, not its parent `SteamStorage` folder. JahreszeitenTracker then automatically detects the existing main farms and plots and accesses FT2 saves **in read-only mode**; saves are never modified.

The published app is **ad-hoc signed**, but it is neither signed with an Apple Developer ID nor notarized by Apple. macOS/Gatekeeper may therefore block the first launch after downloading it.

The current free hobby-project distribution deliberately does not use a paid Apple Developer account. This signing status is an intentional characteristic of the distribution; it does not promise a future Developer ID-signed or notarized version.

## Building and testing

You need macOS and Xcode with a Swift compiler suitable for the project, together with the Apple system frameworks. There are no additional Swift packages or embedded FT2/Steam libraries.

```sh
xcodebuild -project JahreszeitenTracker.xcodeproj -scheme JahreszeitenTracker -configuration Debug -destination 'platform=macOS' build
sh Tests/run-tests.sh
sh Tests/run-localization-tests.sh /path/to/built/JahreszeitenTracker.app
```

For your own modified builds or forks, replace the graphics listed in [BRANDING.en.md](BRANDING.en.md) with your own first, unless you have separate permission. The season images may continue to be used under the GPL.

The optional [WSS DMG workflow](Distribution/README.md) additionally requires Python 3.10 or later with `venv`/`pip` and downloads the external MIT-licensed tools [ds-store 1.3.3](https://pypi.org/project/ds-store/1.3.3/) and [mac-alias 2.2.3](https://pypi.org/project/mac-alias/2.2.3/). These are build dependencies, not original project code, and are not embedded in the app. Their copyright and license notices must be retained if their code is redistributed. Apple system frameworks and Xcode are subject to their own terms.

## License and provenance

Copyright © 2026 WirdSchonSoftware.

The original project materials are licensed under the **GNU General Public License, version 3 only (SPDX: GPL-3.0-only)**. This includes, in particular, the Swift production code, tests and test generators, localizations, original documentation, build/distribution scripts and configuration files, and the season images in `SeasonSpring.imageset`, `SeasonSummer.imageset`, `SeasonAutumn.imageset` and `SeasonWinter.imageset`.

The complete, unmodified official GPLv3 license text is in [LICENSE](LICENSE). This project's license choice is **GPL-3.0-only**; the generic application example at the end of the official license document does not extend that choice to later GPL versions. The project is provided without warranty under the terms of the GPL.

**The WSS logo and JahreszeitenTracker app icon are treated separately and are not released under the GPL.** The exact files and the permission to redistribute unchanged official releases are described in [BRANDING.en.md](BRANDING.en.md). This distinction does not restrict GPL rights in the source code or season images. Current or previously used third-party tools are not relicensed under the project's own license.

The season images, app icon and WSS materials were created for this project, either directly or with AI assistance, and some were subsequently edited manually. The small save-test projections use individual technical values from the project's own FT2 saves; complete original saves, FT2/Steam DLLs and decompiled game code are not included.

## Independence and contact

This project is not affiliated with, developed by, or endorsed by Milkstone Studios. Farm Together 2 is mentioned only to identify the supported application; this does not imply any official rights or support.

- Email: [kontakt@wirdschonsoftware.com](mailto:kontakt@wirdschonsoftware.com)
- Website: [wirdschonsoftware.com](https://wirdschonsoftware.com)
