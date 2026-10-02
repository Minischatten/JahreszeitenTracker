import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

nonisolated var isGermanSystem: Bool {
    let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
    return lang.hasPrefix("de")
}
nonisolated func loc(_ de: String, _ en: String) -> String { isGermanSystem ? de : en }

extension Season {
    func name(isGerman: Bool = isGermanSystem) -> String {
        switch self {
        case .spring: return isGerman ? "Frühling" : "Spring"
        case .summer: return isGerman ? "Sommer" : "Summer"
        case .autumn: return isGerman ? "Herbst" : "Autumn"
        case .winter: return isGerman ? "Winter" : "Winter"
        }
    }
    var next: Season {
        switch self {
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        case .winter: return .spring
        }
    }
    var assetName: String {
        switch self {
        case .spring: return "SeasonSpring"
        case .summer: return "SeasonSummer"
        case .autumn: return "SeasonAutumn"
        case .winter: return "SeasonWinter"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var manager: FarmManager
    @State private var navigation = FarmNavigation()

    var body: some View {
        VStack(spacing: 0) {
            if manager.visibleFarms.count > 1, navigation.detail(in: manager.visibleFarms) != nil {
                HStack {
                    Button { navigation.back() } label: {
                        Label(loc("Alle Farmen", "All farms"), systemImage: "chevron.left")
                    }
                    Spacer()
                }
                .padding()
            }
            if manager.visibleFarms.isEmpty {
                ContentUnavailableView {
                    Label(loc("Keine Hauptfarm", "No main farm"), systemImage: "leaf")
                } description: {
                    Text(manager.hasSaveFolder
                         ? loc("Sobald ein gültiger Spielstand vorliegt, erscheinen deine Farmen hier.", "Your farms appear here when a valid save is available.")
                         : loc("Wähle deinen FT2-Spielstandordner in den Einstellungen.", "Choose your FT2 save folder in Settings."))
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = Date()
                    ScrollView {
                        if let farm = navigation.detail(in: manager.visibleFarms) {
                            FarmDetailView(farm: farm, state: manager.state(for: farm, at: now)) { navigation.back() }
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                                ForEach(manager.visibleFarms) { farm in
                                    OverviewFarmButton(farm: farm, state: manager.state(for: farm, at: now)) {
                                        guard let identity = farm.identity else { return }
                                        manager.selectedFarmIdentity = identity
                                        navigation.open(identity)
                                    }
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            InitialWindowFocus(suppressInitialControlFocus: manager.visibleFarms.count > 1)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .navigationTitle("JahreszeitenTracker")
        .onChange(of: manager.visibleFarms.map(\.identity)) { _, identities in
            if identities.count < 2 || !identities.contains(navigation.openedIdentity) { navigation.back() }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink { Image(systemName: "gearshape") }
                    .help(loc("Einstellungen", "Settings"))
                    .accessibilityLabel(loc("Einstellungen", "Settings"))
            }
        }
    }
}

private struct FarmDetailView: View {
    @EnvironmentObject private var manager: FarmManager
    let farm: FarmData
    let state: SeasonState?
    let onDeleted: () -> Void
    @State private var deletionCandidate: FarmData?
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(spacing: 20) {
            FarmCardView(farm: farm, state: state, compact: false)
            if farm.isInactive {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc("Farm nicht mehr gefunden", "Farm no longer found"))
                        .font(.headline)
                    Text(farm.automaticReference == nil
                         ? loc("Diese Farm ist nicht mehr in den Spielständen von Farm Together 2 registriert. Es liegt kein gültiger Spielstand für einen Countdown vor.",
                               "This farm is no longer registered in the Farm Together 2 saves. No valid save is available for a countdown.")
                         : loc("Diese Farm ist nicht mehr in den Spielständen von Farm Together 2 registriert. Der JahreszeitenTracker verwendet deshalb den zuletzt bekannten Spielstand. Der Countdown läuft auf dieser Grundlage weiter.",
                               "This farm is no longer registered in the Farm Together 2 saves. JahreszeitenTracker uses the last known save and continues the countdown on that basis."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    deletionCandidate = farm
                    confirmsDeletion = true
                } label: {
                    Text(loc("Farm endgültig löschen", "Permanently delete farm"))
                }
            }
        }
        .alert(loc("„\(deletionCandidate?.displayName ?? farm.displayName)“ endgültig löschen?",
                   "Permanently delete ‘\(deletionCandidate?.displayName ?? farm.displayName)’?"),
               isPresented: $confirmsDeletion, presenting: deletionCandidate) { candidate in
            Button(loc("Abbrechen", "Cancel"), role: .cancel) { deletionCandidate = nil }
            Button(loc("Endgültig löschen", "Permanently delete"), role: .destructive) {
                if let identity = candidate.identity, manager.removeInactiveFarm(identity: identity) {
                    onDeleted()
                }
                deletionCandidate = nil
            }
        } message: { _ in
            Text(loc("Die gespeicherten Daten dieser Farm werden vollständig aus dem JahreszeitenTracker entfernt. Diese Aktion kann nicht rückgängig gemacht werden.\n\nDie Spielstände von Farm Together 2 werden dabei nicht verändert.",
                     "All tracker data for this farm will be permanently removed from JahreszeitenTracker. This cannot be undone.\n\nFarm Together 2 saves will not be modified."))
        }
    }
}

// Only our identity payload is accepted; filenames and external text are not drops.
private nonisolated struct FarmCardDrag: Codable, Transferable {
    let identity: FarmIdentity?
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "yasha.jahreszeitentracker.farm-card"))
    }
}

private struct OverviewFarmButton: View {
    @EnvironmentObject private var manager: FarmManager
    let farm: FarmData
    let state: SeasonState?
    let action: () -> Void
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: action) {
            FarmCardView(farm: farm, state: state, compact: true)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isDropTarget ? Color.accentColor : Color.primary.opacity(isHovered ? 0.2 : 0),
                                      lineWidth: isDropTarget ? 2 : 1)
                }
                .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .draggable(FarmCardDrag(identity: farm.identity))
        .dropDestination(for: FarmCardDrag.self) { items, _ in
            guard items.count == 1, let identity = items.first?.identity, let target = farm.identity else { return false }
            return manager.moveFarm(identity, to: target)
        } isTargeted: { isDropTarget = $0 }
        .onHover { isHovered = $0 }
        .accessibilityLabel(farm.displayName)
        .accessibilityHint(loc("Farm öffnen", "Open farm"))
    }
}

// Give AppKit a neutral initial responder before the window is presented.
// Later keyboard focus, navigation and window activation remain untouched.
private struct InitialWindowFocus: NSViewRepresentable {
    let suppressInitialControlFocus: Bool

    func makeNSView(context: Context) -> FocusView {
        let view = FocusView()
        view.suppressInitialControlFocus = suppressInitialControlFocus
        return view
    }

    func updateNSView(_ view: FocusView, context: Context) {
        view.suppressInitialControlFocus = suppressInitialControlFocus
        view.configureInitialResponder()
    }

    final class FocusView: NSView {
        var suppressInitialControlFocus = false
        private var configuredInitialResponder = false
        private var handedOffKeyboardFocus = false

        // A plain NSView draws no control focus ring; native cards retain theirs.
        override var acceptsFirstResponder: Bool { !handedOffKeyboardFocus }
        // The helper is an explicit startup responder, never a normal Tab stop.
        override var canBecomeKeyView: Bool { false }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 48,
                  modifiers.intersection([.command, .control, .option]).isEmpty else {
                super.keyDown(with: event)
                return
            }
            handOffKeyboardFocus(backwards: modifiers.contains(.shift))
        }

        private func handOffKeyboardFocus(backwards: Bool) {
            guard let window, window.firstResponder === self else { return }
            // Resolve the current public key-view loop at the actual key event.
            window.recalculateKeyViewLoop()
            let ownTarget = backwards ? previousValidKeyView : nextValidKeyView
            var anchor: NSView = self
            var target = ownTarget
            // A zero-size background may not be linked into the computed loop.
            // Use the content root as the public entry anchor in that case.
            if target == nil || target === self {
                if let root = window.contentView {
                    anchor = root
                    target = backwards ? root.previousValidKeyView : root.nextValidKeyView
                }
            }
            guard let target, target !== self, target.window === window,
                  target.canBecomeKeyView else { return }
            if backwards {
                window.selectKeyView(preceding: anchor)
            } else {
                window.selectKeyView(following: anchor)
            }
            if window.firstResponder !== self {
                handedOffKeyboardFocus = true
                if window.initialFirstResponder === self { window.initialFirstResponder = nil }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureInitialResponder()
        }

        func configureInitialResponder() {
            guard let window, !configuredInitialResponder else { return }
            configuredInitialResponder = true
            guard suppressInitialControlFocus, !window.isVisible, !window.isKeyWindow else { return }
            window.initialFirstResponder = self
        }
    }
}
