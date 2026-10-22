import Foundation
import SwiftUI
import AppKit

/// Compiled beside ContentView.swift by run-localization-tests.sh solely to
/// exercise its file-private detail view without changing production visibility.
@main
@MainActor
struct LocalizationTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }
    static func main() async throws {
        let arguments = CommandLine.arguments
        let language = arguments[1]
        let catalogURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
        let entries = catalog["strings"] as! [String: [String: Any]]
        check(Bundle.main.developmentLocalization == "de", "German development language in real resource bundle")
        check(Set(Bundle.main.localizations).isSuperset(of: ["de", "en"]), "both compiled localizations present")
        check(Bundle.main.preferredLocalizations.first == language, "Apple language selection, including unsupported-language fallback")
        for (key, entry) in entries where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as! [String: [String: Any]]
            let unit = localizations[language]!["stringUnit"] as! [String: String]
            let actual = Bundle.main.localizedString(forKey: key, value: "MISSING TRANSLATION", table: "Localizable")
            check(actual == unit["value"], "compiled resource matches approved catalog: \(key)")
            check(unit["state"] == "translated", "translation complete")
            check(key.components(separatedBy: "%@").count == actual.components(separatedBy: "%@").count, "parameters retained")
        }
        check(String(localized: "Quellcode: GPL-3.0-only\nBranding separat lizenziert.") ==
              (language == "de" ? "Quellcode: GPL-3.0-only\nBranding separat lizenziert." : "Source code: GPL-3.0-only\nBranding licensed separately."),
              "About license text uses the actual bundled language")
        check(String(localized: "Synchronisiert") == (language == "de" ? "Synchronisiert" : "Synced"), "native runtime lookup")
        check(Season.spring.name() == (language == "de" ? "Frühling" : "Spring"), "season display follows native language")
        check(Season.allCases.map(\.rawValue) == ["spring", "summer", "autumn", "winter"], "persisted seasons never localized")
        check(String(localized: "Zeit bis zum Saisonwechsel") == (language == "de" ? "Zeit bis zum Saisonwechsel" : "Time until the next season"), "accessibility countdown label")
        check(String(localized: "Farm öffnen") == (language == "de" ? "Farm öffnen" : "Open farm"), "accessibility card hint")
        check(String(localized: "Einstellungen") == (language == "de" ? "Einstellungen" : "Settings"), "settings title and tooltip")
        let farmName = "Meine Farm / Café 🌱 100% %@ 348"
        let title = String(localized: "„\(farmName)“ endgültig löschen?")
        check(title == (language == "de" ? "„\(farmName)“ endgültig löschen?" : "Permanently delete “\(farmName)”?"), "farm interpolation remains verbatim")
        check(String(localized: "Abbrechen") == (language == "de" ? "Abbrechen" : "Cancel"), "custom cancel button")
        let hint = "~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/"
        check(String(localized: "Normalerweise unter macOS: \(hint)").contains(hint), "path never translated")
        check(CountdownDisplay.text(remaining: 1020) == "17:00", "countdown unchanged")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        try checkStartupFocus()
        let suite = "FT2LocalizationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reminderService = LocalizationReminderNotifications()
        let reminders = ReminderManager(service: reminderService, defaults: defaults)
        let router = ReminderRouter()
        let session = FarmPresentationSession()
        let manager = FarmManager(defaults: defaults)
        manager.catalog.selectSource(path: "/synthetic/read-only/Café", bookmark: Data([1]))
        let source = manager.catalog.activeSourceID!
        let now = Date()
        let ticks = TrackerClock.ticksAtUnixEpoch + Int64(now.timeIntervalSince1970) * 10_000_000
        let metadata = (0..<4).map { FT2FarmMetadata(slotIndex: $0 * 16, creationTime: ticks - 10_000_000,
            name: $0 == 0 ? farmName + " – Eine besonders lange Hauptfarm mit unverändertem Namen" : "Farm \($0 + 1)") }
        let references = (0..<4).map { SaveReference(gameTime: 100, savedTicks: ticks, nextBoundary: 500,
            seasonIndex: $0, sourceName: "farm_\($0 * 16)_0.data", saveVersion: $0 == 1 ? 348 : 347) }
        manager.catalog.merge((0..<4).map { FarmReading(metadata: metadata[$0], reference: references[$0], message: "",
            rejectedVersions: $0 == 2 ? [349] : []) }, sourceID: source)
        let persistedNames = manager.farms.map(\.name)
        check(manager.farms[0].displayName == metadata[0].name, "farm name unaffected by language")
        check(manager.farms[1].versionExplanation()?.contains("348") == true, "unconfirmed dynamic version")
        check(manager.farms[2].versionExplanation()?.contains("349") == true, "rejected dynamic version")
        if language == "en" {
            check(manager.farms[1].versionExplanation() == "Farm Together 2 uses save version 348. JahreszeitenTracker could read the required data, but this version has not yet been verified.", "full English sentence interpolation")
        }
        var noReference = manager.farms[2]
        noReference.automaticReference = nil
        check(noReference.versionExplanation()?.contains(language == "de" ? "Es liegt noch kein gültiger Spielstand" : "No valid save is available") == true, "complete rejected-without-reference template")
        noReference.compatibility = FarmCompatibility(metadataVersion: 348)
        check(noReference.versionExplanation()?.contains(language == "de" ? "Es liegt noch kein gültiger Spielstand" : "No valid save is available") == true, "complete unconfirmed-without-reference template")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 900), to: output.appendingPathComponent("\(language)-overview.png"))
        try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 380, height: 900), to: output.appendingPathComponent("\(language)-narrow.png"))
        try render(FarmDetailView(farm: manager.farms[2], state: manager.state(for: manager.farms[2], at: now), onDeleted: {}).environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 950), to: output.appendingPathComponent("\(language)-detail.png"))
        manager.catalog.merge((0..<3).map { FarmReading(metadata: metadata[$0], reference: references[$0], message: "",
            rejectedVersions: $0 == 2 ? [349] : []) }, sourceID: source)
        try render(FarmDetailView(farm: manager.farms[3], state: manager.state(for: manager.farms[3], at: now), onDeleted: {}).environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 1000), to: output.appendingPathComponent("\(language)-inactive.png"))
        manager.catalog.sources[0].metadataNotice = MetadataNotice(version: 348, rejected: false, deferredFarms: 1)
        check(manager.catalogVersionNotice?.contains("348") == true, "catalog version parameter")
        if language == "en" { check(manager.catalogVersionNotice?.hasPrefix("Save version 348 has not yet been verified.") == true, "English global version notice") }
        try render(AboutView(), size: NSSize(width: 380, height: 800), to: output.appendingPathComponent("\(language)-about.png"))
        try render(SettingsView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 560, height: 900), to: output.appendingPathComponent("\(language)-settings.png"))
        try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 950), to: output.appendingPathComponent("\(language)-catalog-warning.png"))
        manager.catalog.sources[0].metadataNotice = MetadataNotice(version: 349, rejected: true, deferredFarms: 0)
        check(manager.catalogVersionNotice?.contains("349") == true, "rejected catalog parameter")
        check(manager.farms.map(\.name) == persistedNames, "rendering never localizes stored names")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(localized: "Die gespeicherten Daten dieser Farm werden vollständig aus dem JahreszeitenTracker entfernt. Diese Aktion kann nicht rückgängig gemacht werden.\n\nDie Spielstände von Farm Together 2 werden dabei nicht verändert.")
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.addButton(withTitle: String(localized: "Endgültig löschen"))
        alert.layout()
        alert.window.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(100))
        if let content = alert.window.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.white.cgColor
            try snapshot(content, to: output.appendingPathComponent("\(language)-delete-dialog.png"))
        }
        check(String(localized: "Farm ausblenden") == (language == "de" ? "Farm ausblenden" : "Hide Farm"), "native checkbox label")
        check(String(localized: "Ausgeblendete Farmen einblenden") == (language == "de" ? "Ausgeblendete Farmen einblenden" : "Show Hidden Farms"), "native menu label")
        check(String(localized: "Keine Farmen eingeblendet") == (language == "de" ? "Keine Farmen eingeblendet" : "No Farms Shown"), "hidden empty title")
        check(String(localized: "Ausgeblendet") == (language == "de" ? "Ausgeblendet" : "Hidden"), "hidden accessibility marker")
        for farm in manager.knownFarms { manager.setHidden(true, identity: farm.identity!) }
        try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 780), to: output.appendingPathComponent("\(language)-all-hidden.png"))
        session.showHiddenFarms = true
        try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 950), to: output.appendingPathComponent("\(language)-hidden-overview.png"))
        try render(FarmDetailView(farm: manager.farms[3], state: manager.state(for: manager.farms[3], at: now), onDeleted: {}).environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router), size: NSSize(width: 640, height: 1100), to: output.appendingPathComponent("\(language)-hidden-inactive-detail.png"))
        reminders.updateFarms(manager.catalog.farms)
        await reminders.reconcile()
        await reminders.setReminder(for: manager.farms[0], seasonIndex: 1)
        check(reminders.active(for: manager.farms[0].identity) != nil, "active reminder appears for confirmed hidden farm")
        try render(FarmReminderView(farm: manager.farms[0]).environmentObject(reminders), size: NSSize(width: 560, height: 180),
                   to: output.appendingPathComponent("\(language)-active-reminder.png"))
        for index in 0..<4 {
            let reminder = SeasonReminder(id: UUID(), farmIdentity: manager.farms[0].identity!, seasonIndex: index,
                createdAt: now, scheduledAt: now.addingTimeInterval(600), reference: references[0], farmName: farmName, state: .pending)
            let content = MacNotificationService.content(for: reminder)
            let expectedTitles = language == "de" ? ["Frühling hat begonnen", "Sommer hat begonnen", "Herbst hat begonnen", "Winter hat begonnen"]
                : ["Spring has begun", "Summer has begun", "Autumn has begun", "Winter has begun"]
            check(content.title == expectedTitles[index], "notification title localized")
            let seasonNames = language == "de" ? ["Frühling", "Sommer", "Herbst", "Winter"] : ["spring", "summer", "autumn", "winter"]
            let expectedBody = language == "de" ? "Auf „\(farmName)“ ist jetzt \(seasonNames[index])."
                : "It is now \(seasonNames[index]) on “\(farmName)”."
            check(content.body == expectedBody, "complete localized notification template preserves dynamic farm name")
        }
        manager.catalog.sources[0].metadataNotice = MetadataNotice(version: 353, rejected: false, deferredFarms: 0)
        check(manager.catalogVersionNotice?.contains("353") == true, "353 warning stays visible")
        session.showHiddenFarms = false
        for displayedCount in [1, 4] {
            for index in manager.farms.indices {
                manager.setHidden(index >= displayedCount, identity: manager.farms[index].identity!)
            }
            check(FarmNavigation().shouldSuppressInitialControlFocus(
                in: manager.visibleFarms(), knownFarms: manager.knownFarms),
                  "warning overview protects startup with \(displayedCount) cards")
            try render(ContentView().environmentObject(manager).environmentObject(session).environmentObject(reminders).environmentObject(router),
                       size: NSSize(width: 640, height: 950),
                       to: output.appendingPathComponent("\(language)-353-warning-\(displayedCount)-cards.png"),
                       expectNeutralFocus: true)
        }
        print("Passed \(checks) bundled localization/UI checks (\(language)); resources: \(Bundle.main.resourcePath ?? "")")
    }

    static func checkStartupFocus() throws {
        check(!FT2VersionPolicy.isConfirmed(353), "353 remains unconfirmed during focus regression")
        for cardCount in 1...2 {
            for backwards in [false, true] {
                let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
                let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = root
                defer { window.contentView = nil }
                let focus = InitialWindowFocus.FocusView()
                root.addSubview(focus) // Initially unarmed: must not consume startup.
                let buttons = (0..<cardCount).map { index in
                    let button = FocusTestButton(frame: NSRect(x: 20 + index * 280, y: 100, width: 260, height: 200))
                    root.addSubview(button)
                    return button
                }
                focus.suppressInitialControlFocus = true
                focus.layout()
                check(window.initialFirstResponder === focus && window.firstResponder === focus,
                      "late overview activation establishes neutral startup responder")
                // Simulate an inserted warning and a subsequent control assignment.
                root.addSubview(NSTextField(labelWithString: "Spielstandversion 353"))
                check(window.makeFirstResponder(buttons[0]), "control can accept normal keyboard focus")
                focus.layout()
                check(window.firstResponder === focus, "later warning layout retains neutral startup focus")
                check(!focus.canBecomeKeyView, "neutral helper is never an ordinary tab stop")
                let tab = NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: backwards ? [.shift] : [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "\t",
                    charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
                focus.keyDown(with: tab)
                check(buttons.contains { window.firstResponder === $0 }, "Tab/Shift-Tab hands off to native key-view loop")
                let responder = window.firstResponder
                focus.layout()
                check(window.firstResponder === responder && window.initialFirstResponder !== focus,
                      "layout never reclaims deliberate keyboard focus")
            }
        }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.contentView = nil }
        let focus = InitialWindowFocus.FocusView()
        focus.suppressInitialControlFocus = true
        root.addSubview(focus)
        let button = FocusTestButton(frame: NSRect(x: 20, y: 100, width: 260, height: 200))
        root.addSubview(button)
        focus.layout()
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        focus.observeUserInteraction(click)
        window.makeFirstResponder(button)
        focus.layout()
        check(window.firstResponder === button && window.initialFirstResponder !== focus,
              "deliberate mouse input also ends startup protection")
    }

    static func render<V: View>(_ view: V, size: NSSize, to url: URL, expectNeutralFocus: Bool = false) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.white))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        // Allow SwiftUI's layout/render transactions to finish in the isolated test host.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        if expectNeutralFocus {
            check(window.firstResponder is InitialWindowFocus.FocusView,
                  "actual SwiftUI warning overview has neutral startup responder")
        }
        try snapshot(host, to: url)
        window.contentView = nil
    }
    static func snapshot(_ view: NSView, to url: URL) throws {
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

// Make the isolated native-button tests independent of macOS's global Tab setting.
@MainActor
private final class FocusTestButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

@MainActor
private final class LocalizationReminderNotifications: ReminderNotifications {
    func authorize() async throws -> Bool { true }
    func schedule(_ reminder: SeasonReminder) async throws {}
    func remove(_ requestIDs: [String]) {}
    func pendingIDs() async -> Set<String> { [] }
}
