import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

extension Season {
    func name() -> String {
        switch self {
        case .spring: return String(localized: "Frühling")
        case .summer: return String(localized: "Sommer")
        case .autumn: return String(localized: "Herbst")
        case .winter: return String(localized: "Winter")
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
    @EnvironmentObject private var session: FarmPresentationSession
    @EnvironmentObject private var router: ReminderRouter
    @Environment(\.openWindow) private var openWindow
    @State private var routeWindow = ReminderWindowHandle()
    @State private var routeMissing = false
    @State private var navigation = FarmNavigation()

    var body: some View {
        VStack(spacing: 0) {
            if let notice = manager.catalogVersionNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let detail = navigation.detail(in: manager.visibleFarms(showHiddenFarms: session.showHiddenFarms), knownFarms: manager.knownFarms, routingFarms: manager.catalog.farms),
               manager.knownFarms.count > 1 || detail.hidden || navigation.openedIdentity != nil {
                HStack {
                    Button { navigation.back() } label: {
                        Label(String(localized: "Alle Farmen"), systemImage: "chevron.left")
                    }
                    Spacer()
                }
                .padding()
            }
            if navigation.detail(in: manager.visibleFarms(showHiddenFarms: session.showHiddenFarms), knownFarms: manager.knownFarms, routingFarms: manager.catalog.farms) == nil && manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).isEmpty {
                ContentUnavailableView {
                    Label(manager.knownFarms.isEmpty ? String(localized: "Keine Hauptfarm")
                          : String(localized: "Keine Farmen eingeblendet"), systemImage: "leaf")
                } description: {
                    Text(!manager.knownFarms.isEmpty
                         ? String(localized: "Ausgeblendete Farmen können über „Darstellung → Ausgeblendete Farmen einblenden“ angezeigt werden.")
                         : manager.hasSaveFolder
                         ? String(localized: "Sobald ein gültiger Spielstand vorliegt, erscheinen deine Farmen hier.")
                         : String(localized: "Wähle deinen FT2-Spielstandordner in den Einstellungen."))
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = Date()
                    ScrollView {
                        if let farm = navigation.detail(in: manager.visibleFarms(showHiddenFarms: session.showHiddenFarms), knownFarms: manager.knownFarms, routingFarms: manager.catalog.farms) {
                            FarmDetailView(farm: farm, state: manager.state(for: farm, at: now),
                                           onHiddenChanged: { hidden in
                                               guard let identity = farm.identity else { return }
                                               navigation.open(identity)
                                               manager.setHidden(hidden, identity: identity)
                                           }, onDeleted: { navigation.back() })
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                                ForEach(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms)) { farm in
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
            InitialWindowFocus(suppressInitialControlFocus: navigation.shouldSuppressInitialControlFocus(
                in: manager.visibleFarms(showHiddenFarms: session.showHiddenFarms),
                knownFarms: manager.knownFarms, routingFarms: manager.catalog.farms))
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .background {
            ReminderWindowAnchor(handle: routeWindow)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .navigationTitle("JahreszeitenTracker")
        .onAppear {
            router.openWindow = {
                if let window = routeWindow.window, window.isVisible || window.isMiniaturized {
                    window.deminiaturize(nil)
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            }
            applyReminderRoute()
        }
        .onChange(of: router.requestToken) { _, _ in applyReminderRoute() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if note.object as? NSWindow === routeWindow.window { applyReminderRoute() }
        }
        .alert(String(localized: "Farm nicht verfügbar"), isPresented: $routeMissing) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Die Farm dieser Erinnerung ist nicht mehr im JahreszeitenTracker vorhanden."))
        }
        .onChange(of: manager.knownFarms.map(\.identity)) { _, _ in
            if let opened = navigation.openedIdentity, !manager.catalog.farms.contains(where: { $0.identity == opened }) { navigation.reset() }
        }
        .onChange(of: manager.catalog.activeSourceID ?? manager.catalog.displaySourceID) { _, _ in
            navigation.reset()
        }
        .onChange(of: session.showHiddenFarms) { previouslyShown, _ in
            // A lone hidden farm may have opened automatically while the menu
            // was enabled. Preserve that detail when the user disables it.
            let previousFarms = manager.knownFarms.filter { previouslyShown || !$0.hidden }
            if let identity = navigation.detail(in: previousFarms, knownFarms: manager.knownFarms, routingFarms: manager.catalog.farms)?.identity {
                navigation.open(identity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink { Image(systemName: "gearshape") }
                    .help(String(localized: "Einstellungen"))
                    .accessibilityLabel(String(localized: "Einstellungen"))
            }
        }
    }
    private func applyReminderRoute() {
        guard let window = routeWindow.window, window.isVisible,
              let identity = router.identity else { return }
        if manager.catalog.farms.contains(where: { $0.identity == identity }) {
            navigation.open(identity)
        } else {
            routeMissing = true
        }
        router.consume()
    }

}

private struct FarmDetailView: View {
    @EnvironmentObject private var manager: FarmManager
    let farm: FarmData
    let state: SeasonState?
    var onHiddenChanged: ((Bool) -> Void)? = nil
    let onDeleted: () -> Void
    @State private var deletionCandidate: FarmData?
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(spacing: 20) {
            FarmCardView(farm: farm, state: state, compact: false)
            FarmReminderView(farm: farm)
            Toggle(String(localized: "Farm ausblenden"), isOn: Binding(
                get: { manager.knownFarms.first { $0.identity == farm.identity }?.hidden ?? farm.hidden },
                set: { hidden in
                    if let onHiddenChanged { onHiddenChanged(hidden) }
                    else if let identity = farm.identity { manager.setHidden(hidden, identity: identity) }
                }))
                .toggleStyle(.checkbox)
            if let explanation = farm.versionExplanation() {
                Label(explanation, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if farm.isInactive {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Farm nicht mehr gefunden"))
                        .font(.headline)
                    Text(farm.automaticReference == nil
                         ? String(localized: "Diese Farm ist nicht mehr in den Spielständen von Farm Together 2 registriert. Es liegt kein gültiger Spielstand für einen Countdown vor.")
                         : String(localized: "Diese Farm ist nicht mehr in den Spielständen von Farm Together 2 registriert. Der JahreszeitenTracker verwendet deshalb den zuletzt bekannten Spielstand. Der Countdown läuft auf dieser Grundlage weiter."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    deletionCandidate = farm
                    confirmsDeletion = true
                } label: {
                    Text(String(localized: "Farm endgültig löschen"))
                }
            }
        }
        .alert(String(localized: "„\(deletionCandidate?.displayName ?? farm.displayName)“ endgültig löschen?"),
               isPresented: $confirmsDeletion, presenting: deletionCandidate) { candidate in
            Button(String(localized: "Abbrechen"), role: .cancel) { deletionCandidate = nil }
            Button(String(localized: "Endgültig löschen"), role: .destructive) {
                if let identity = candidate.identity, manager.removeInactiveFarm(identity: identity) {
                    onDeleted()
                }
                deletionCandidate = nil
            }
        } message: { _ in
            Text(String(localized: "Die gespeicherten Daten dieser Farm werden vollständig aus dem JahreszeitenTracker entfernt. Diese Aktion kann nicht rückgängig gemacht werden.\n\nDie Spielstände von Farm Together 2 werden dabei nicht verändert."))
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
    @EnvironmentObject private var session: FarmPresentationSession
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
            return manager.moveFarm(identity, to: target, showHiddenFarms: session.showHiddenFarms)
        } isTargeted: { isDropTarget = $0 }
        .onHover { isHovered = $0 }
        .accessibilityLabel(farm.displayName)
        .accessibilityValue(farm.hidden ? String(localized: "Ausgeblendet") : "")
        .accessibilityHint(String(localized: "Farm öffnen"))
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
        view.needsLayout = true
    }

    final class FocusView: NSView {
        var suppressInitialControlFocus = false
        private var finishedStartupFocus = false
        private var interactionMonitor: Any?
        private var handedOffKeyboardFocus = false

        // A plain NSView draws no control focus ring; native cards retain theirs.
        override var acceptsFirstResponder: Bool { !handedOffKeyboardFocus }
        // The helper is an explicit startup responder, never a normal Tab stop.
        override var canBecomeKeyView: Bool { false }

        override func keyDown(with event: NSEvent) {
            observeUserInteraction(event)
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
            if window != nil, !finishedStartupFocus, interactionMonitor == nil {
                interactionMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                    self?.observeUserInteraction(event)
                    return event
                }
            }
            configureInitialResponder()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { removeInteractionMonitor() }
            super.viewWillMove(toWindow: newWindow)
        }

        override func layout() {
            super.layout()
            configureInitialResponder()
            guard !finishedStartupFocus, suppressInitialControlFocus, let window else { return }
            // SwiftUI can assign a control responder during a later layout.
            // Protect startup only, until the first deliberate input event.
            if window.firstResponder !== self { window.makeFirstResponder(self) }
        }

        func observeUserInteraction(_ event: NSEvent) {
            guard let window,
                  event.window === window || (event.window == nil && NSApp.keyWindow === window) else { return }
            finishedStartupFocus = true
            if window.initialFirstResponder === self { window.initialFirstResponder = nil }
            removeInteractionMonitor()
        }

        private func removeInteractionMonitor() {
            if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
            interactionMonitor = nil
        }

        func configureInitialResponder() {
            guard let window, !finishedStartupFocus else { return }
            guard suppressInitialControlFocus else {
                if window.initialFirstResponder === self { window.initialFirstResponder = nil }
                return
            }
            window.initialFirstResponder = self
        }
    }
}
