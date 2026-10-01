import SwiftUI

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
                            FarmCardView(farm: farm, state: manager.state(for: farm, at: now), compact: false)
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

private struct OverviewFarmButton: View {
    let farm: FarmData
    let state: SeasonState?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            FarmCardView(farm: farm, state: state, compact: true)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.primary.opacity(isHovered ? 0.2 : 0), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(farm.displayName)
        .accessibilityHint(loc("Farm öffnen", "Open farm"))
    }
}

// AppKit chooses the first eligible button when a window first becomes key.
// Clear that automatic initial choice once, without disabling keyboard focus or
// changing focus when returning to the overview or reactivating the window.
private struct InitialWindowFocus: NSViewRepresentable {
    let suppressInitialControlFocus: Bool

    func makeNSView(context: Context) -> FocusView { FocusView() }
    func updateNSView(_ view: FocusView, context: Context) {
        view.suppressInitialControlFocus = suppressInitialControlFocus
    }

    final class FocusView: NSView {
        var suppressInitialControlFocus = false
        private var didActivate = false
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window, !didActivate else { return }
            if window.isKeyWindow {
                handleInitialActivation()
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleInitialActivation() }
            }
        }

        private func handleInitialActivation() {
            guard !didActivate else { return }
            didActivate = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            // Do not interfere with an activation initiated by keyboard input.
            if suppressInitialControlFocus, NSApp.currentEvent?.type != .keyDown {
                window?.makeFirstResponder(nil)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
