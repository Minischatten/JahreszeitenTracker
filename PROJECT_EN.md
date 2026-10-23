# JahreszeitenTracker – technical working context

**[Deutsche Version](PROJECT.md)**

`PROJECT_EN.md` is the English translation. Update both versions together when
technical or project-related statements change; `PROJECT.md` remains authoritative.
If the versions unintentionally differ in substance, the German `PROJECT.md` takes
precedence.

This file provides a compact starting point for project work and Codex. Code,
tests and build configurations remain authoritative. Keep this context up to date
when changing functionality; do not maintain a complete development history here.

## Purpose and platform

Free hobby project for Farm Together 2 (FT2): derive the current season and time
remaining for each main farm from saves and display them independently of the game
running. Includes automatic detection/synchronization, farm overview and details,
persistent card ordering via drag & drop, hidden/inactive farms and one-time season
reminders. No manual season/time correction in the UI.

- Native macOS app, minimum macOS 14.0; Universal Release for `arm64` and `x86_64`.
- SwiftUI with targeted AppKit bridges; Foundation/Combine, system zlib and
  UserNotifications. No Swift Packages or embedded FT2/Steam libraries.
- `JahreszeitenTrackerApp.swift`: shared instances, windows, Settings and Commands.
- `TrackerCore.swift`: time/season arithmetic and central version policy without UI,
  timers or persistence; calculations receive their point in time explicitly.
- `FT2SaveParser.swift` / `FT2FarmMetadata.swift`: plot and metadata parsers, respectively.
- `FT2SaveAccess.swift`: macOS file access, consistent snapshots and plot selection.
- `FarmCatalog.swift`: identities, references, merging, ordering, status and navigation.
- `FarmManager.swift`: MainActor ObservableObject, persistence and scan coordination;
  files are read in a detached task. Polling approximately every 10 seconds.
- `ContentView`, `FarmCardView`, `SettingsView`, `AboutView`, `ReminderView`: presentation.

## FT2 access: read-only

The user explicitly selects their Steam ID folder through `NSOpenPanel`.
Usual path:

```text
~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/
```

The dialog suggests `SteamStorage` if it exists, otherwise the user's home directory.
No automatic Steam ID selection or recursive save search.

App Sandbox and `user-selected.read-only` remain enabled. Security-scoped bookmarks
are created with `.securityScopeAllowOnlyReadAccess`. `FT2SaveAccess` opens files
with `O_RDONLY`/`O_NOFOLLOW`, accepts only regular files and checks size and change
timestamps before/after reading. Symlinked plot directories are rejected;
`farms.mlk` is compared again at the end of the scan. Decompression is in memory only.
**Never modify, delete or write back FT2 files.**

## Format, detection and identity

- `farms.mlk` registers main farms: version and entries containing `slotIndex`,
  `farm.creation_time` and `farm.name`. Byte transformation, Gzip, then normalized
  JSON with some unquoted keys; the text read is never executed.
- Associated plot files are in `farms/`: exactly `farm_<slot>_<index>.data`.
  Canonical nonnegative integer indices, no fixed plot limit, no recursion.
  Other slots, global `farm_<slot>.data`, backups and invalid names are excluded.
  Only existing plot files count; nonexistent plots are not artificially added.
- Plot saves: Gzip and the observed FT2 binary variant, **not standard MessagePack**.
  Field 0 is the version; synchronization fields are 15, 16, 18 and 21.
  The parser traverses the entire document, skips supported unknown fields and
  validates types, duplicate keys, bounds and the complete end of the document.
  Size limits: compressed 16 MiB, decompressed 64 MiB; further structure/depth limits
  are defined in the respective parser.
- `FarmIdentity = sourceID (UUID) + slotIndex + creationTime`. Name and slot alone
  do not establish identity. `sourceID` belongs to the stored folder source;
  reselecting the same stored path reuses its UUID.
- Reusing a slot with a different `creation_time` creates a new farm. Plot saves
  predating its creation time are ignored. Exactly matching returning identities
  can be registered again through confirmed metadata.
- Select the latest reference by the **embedded field-16 time**, not file modification
  time or filename. Take all four timing values together from the same plot file.
  Conflicting ties at the latest timestamp are rejected; older references do not
  replace newer ones. With the same timestamp and state, the reference remains valid.

## Versions and trust model

Central approval: `FT2VersionPolicy.confirmed` in `TrackerCore.swift`:
**347, 350, 352**. **348, 349 and 351 are not confirmed.**
`mayRead` permits confirmed versions and versions greater than 347 for defensive
reading attempts. Structurally readable does not mean confirmed; new approvals
require real-data analysis and practical testing, not automatic confirmation of
intermediate versions.

- Confirmed and currently verified: normal synchronization status.
- Unconfirmed but fully validated: references may be updated for already registered,
  exactly matching identities; a version warning remains visible.
- Cannot be read safely: no new reference; an existing valid reference is retained.
  Do not invent a countdown without a reference. Version observations are persisted;
  an old valid file must not hide warnings about detected incompatible files.
- **Only complete, successful metadata scans of a confirmed version are authoritative
  for registration, names and new identities.** Unconfirmed metadata does not
  delete/deactivate known farms, apply renames or create a new persistent farm identity
  or its countdown. It does not reactivate inactive farms.
- Unreadable metadata is not an empty catalog. One or all invalid plot files do not
  mean a farm has been deleted; last-known references are retained. Details:
  `FarmCatalog.apply/merge`, `FT2SaveAccess.areaSnapshot`.

## Time model and display

- Field 15 `worldTicks`: global internal timeline in seconds.
- Field 16: save time as .NET DateTime ticks; `10_000_000` ticks/second,
  Unix epoch `621_355_968_000_000_000`. Observed saves correspond to UTC;
  DateTime.Kind is not included in these bytes.
- Field 18 `nextSeasonChange`: next boundary on the internal timeline.
- Field 21 `currentSeason`: 0 spring, 1 summer, 2 autumn, 3 winter.
- Season duration **1020 seconds**, four-season cycle **4080 seconds**. Stored
  season start = `savedAt + (nextBoundary - gameTime) - 1020`.
  `SeasonCalculator` uses absolute system time and positively normalized modulo;
  no continuous timer accumulation, including support for multiple offline changes.
- Validation includes `gameTime >= 0`, boundary strictly after it and at most 1020
  seconds away, index 0–3, save no more than 300 seconds in the future; exact limits
  are in the code.
- **Display only:** `CountdownDisplay.seconds = Int(min(remaining + 2, 1020))`.
  Do not apply +2 seconds or the 17:00 clamp to season, reference, boundary or reminder.
  Do not introduce a second time model. Measurement results and limitations of the
  empirical compensation are in `SAVE_SYNCHRONISATION.md`; no Steam runtime library
  is needed.

## Status, presentation and sensitive UI rules

`FarmSyncState` distinguishes “Synced”, “Last Saved State”, “Waiting for Save”,
“Farm No Longer Found”, “New Save Version Detected”, “Last Saved State – New Save Version”
and “Unsupported Save Version”. Only confirmed and currently verified references
receive the green Synced symbol. Folder unavailability does not prevent an existing
reference from continuing to drive the countdown.

- `registered=false` results from confirmed absence in the authoritative catalog.
  An inactive farm remains gray and clickable, with its last reference and position.
  Permanent removal requires confirmation and removes it entirely from the tracker,
  never from FT2.
- `hidden` is persistent per full identity; a missing field is loaded as `false`.
  Changes are identity-based through the manager only; do not write back an outdated
  farm copy. Hiding a farm does not close an open detail view.
- `FarmPresentationSession.showHiddenFarms` is shared, **nonpersistent** session
  state, initially `false`. The menu and views share the same instance.
  Commands observe only this model, **not the regularly publishing FarmManager**:
  otherwise the open View menu may rebuild and lose system entries. Do not introduce
  additional persistence or AppKit menu repair.
- One known and displayed farm: automatic details. Multiple known farms: overview,
  even if only one is visible. All hidden: dedicated empty state.
  Explicit notification routing can open hidden farms.
- The catalog array is the sole persistent order. Filtered D&D reassigns only the
  positions of displayed farms; hidden farms keep their catalog positions.
  New identities are appended; renaming/inactivity does not change the order.
- `InitialWindowFocus` in `ContentView.swift`: public AppKit startup responder,
  protecting even later initial layouts until the first deliberate input.
  Tab/Shift-Tab hand off to valid native key views; the helper is not a permanent
  Tab stop. Preserve native button focusability, Space, click, hover and D&D.
  No `.focusable(false)`, private SwiftUI classes or time-based delays.

## One-time season reminders

`SeasonReminder`/`ReminderRules` contain identity and scheduling logic;
`ReminderManager` manages state/persistence, `MacNotificationService` integrates
UserNotifications. Request permission only when setting a reminder.

A new reminder requires a registered farm with a confirmed reference and no unresolved
version issues. The target is the next start of the selected season; if that season
is currently running, its next cycle. Calculate the time from the same uncompensated
reference, round the system trigger up to a whole second, `repeats=false`.

Setting a reminder replaces the previous one for that farm. Request ID
`season-reminder.<Reminder-UUID>` stays the same when correcting/renaming.
A new valid reference corrects the originally selected occurrence; do not automatically
roll forward to the next cycle. Hiding preserves a reminder; confirmed inactivity
cancels it, a permanently missing farm and manual cancellation remove it.
Elapsed times become `expired`; a missing future system request becomes `cancelled`
during restoration, not automatically rescheduled. Terminal records may remain
persisted; this does not imply repetition.

System-registered local notifications do not need a dedicated background process.
Routing uses the full FarmIdentity and can open windows/activate the app, including
for hidden farms. Tests on real macOS must cover delivery with an active window,
a closed window and after ⌘Q, as well as click/cold-start routing; do not infer
system permissions and delivery from unit tests alone.

## Persistence and localization

`UserDefaults.standard` of the sandboxed app, each stored as JSON in Data:

- `ft2FarmCatalog_v2`: sources (UUID, path, read-only bookmark, metadata notices),
  active/displayed source, selected identity, farms including order, name,
  hidden/registration state, version information and last reference.
- `seasonReminders_v1`: reminder ID, full farm identity, target index, timestamps,
  reference, name and state. System requests are additionally managed by macOS.

Restoration validates the catalog/references; availability and current verification
are reset at startup. Removing access retains references but deactivates the active
source. Containers and preferences follow the bundle ID; changing it is not a
transparent migration. No container cleanup as a side effect.

German is the development language (`developmentRegion=de`), English the second language.
`Localizable.xcstrings`, native Apple language selection, no custom switch/detection.
Use complete localized sentence templates with unchanged dynamic parameters;
never use localized strings as identities or values for domain decisions.

## Release, distribution and licensing

- Currently configured version **1.0.2 (Build 4)** in the project and `Distribution/app-dmg.json`.
- Permanent bundle ID: `com.wirdschonsoftware.jahreszeitentracker` (Debug/Release).
  Custom D&D type: `com.wirdschonsoftware.jahreszeitentracker.farm-card`.
- WSS DMG: `Distribution/build-dmg.sh`, `wss-layout.json`, `app-dmg.json`; do not
  reinterpret the layout for every release. By default, committed sources via
  `git archive HEAD`, alternatively an explicit `APP_PATH` with separately documented provenance.
- Ad-hoc signing through Xcode with project entitlements, no Developer ID/notarization
  and no promise of either. Gatekeeper approval as described in the READMEs; do not
  document global security disablement. No update check implemented.
- `verify-app.py` checks the Universal app, version, minimum OS version, bundle/signing ID,
  sandbox/read-only, languages and AppIcon before packaging **and in the finished DMG**.
  Volume icon from AppIcon, `Programme` → `/Applications`; do not distribute temporary
  build tools. Details in `Distribution/README.md` / `README.en.md`.
- Generated `Distribution/DMG-Background.png`, `DMG-Commit.txt`, `*.dmg` and
  `*.dmg.sha256` are ignored; scripts/templates/configurations remain versioned.
- **GPL-3.0-only** for original code/test/documentation/build materials and season images.
  WSS logo, AppIcon and transparent README icon variant are separately licensed:
  exact files/conditions in `BRANDING.md` / `BRANDING.en.md`. No blanket GPL grant
  for all assets. `Distribution/WSS_Logo.png` is the unchanged original.
- Do not distribute original saves, FT2/Steam DLLs or decompiled source code.
  Test projections contain small individual technical values, not complete saves.

## WSS website

`wirdschonsoftware.com` has a minimal static landing page in German and English.
WirdSchonSoftware is explicitly presented as a shared name for private software
projects, not as a company or business. JahreszeitenTracker is presented as a public
project with a link to its GitHub repository. A legal notice and privacy policy are
available. No analytics, tracking, cookies or externally loaded assets. HTTPS is
configured; HTTP redirects to HTTPS, and HSTS is enabled.

## Verification when making changes

- `sh Tests/run-tests.sh`: core/parser/catalog, manager, reminder and licensing checks.
- `sh Tests/run-localization-tests.sh /pfad/zur/JahreszeitenTracker.app`: actual bundle,
  DE/EN, language fallback, UI/navigation/focus checks and previews.
  String Catalog JSON alone does not establish usable bundle localization.
- For releases, check Debug and Universal archives, inspect Mach-O for both architectures
  and the macOS 14 minimum; explicitly check signature/entitlements on the mounted
  DMG app. Check mounting/copying, SHA-256, icons and the unchanged WSS layout.
- Retain regressions particularly for version trust/mixed saves, slot reuse, read failures,
  reference conflicts, hidden/D&D/navigation and reminder lifecycle.
  Version approvals require real FT2 data and practical season/countdown testing.
- Leave the menu open while scans run; manually test initial focus with 1/multiple
  visible cards, hidden filtering and a version warning, plus Tab/Shift-Tab/Space.
- Do not include personal paths/Steam IDs, third-party analysis artifacts or temporary
  diagnostics in public sources. Check diff and status before committing; do not
  version generated distribution artifacts. This file does not authorize commits,
  pushes, history rewrites or publication.

## Open ideas / possible next work

**Work options, not promised features or a public roadmap.**
The following priorities and external observations come from the current work request;
they must not be read as already implemented repository state.

1. **First-run onboarding**
   Investigate whether Settings should open automatically for a genuinely unconfigured
   installation. Distinguish a true first run without a configured source from a
   configured folder that is temporarily unavailable/unreadable.
2. **Automatic update checking**
   Investigate a concept using GitHub releases, particularly Sparkle's suitability.
   Consider security, signing, appcast and distribution requirements;
   do not assume a concrete implementation decision yet.
3. **DMG file icon after download**
   In the observed download path, the outer Finder icon is lost while the volume icon
   is retained. Investigate portable preservation or deliberately omitting it for a
   future release. Not a current functional bug or a reason for a new release.
4. **Planting/harvesting information**
   A possible larger extension: reliably determine from FT2 data what can currently
   be planted seasonally or harvested for relevant plants/herbs. Consider changes
   between FT2 versions. No promise for version 2.0 or any particular release.
