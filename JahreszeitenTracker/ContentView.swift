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

    var body: some View {
        VStack(spacing: 0) {
            if manager.visibleFarms.count > 1 {
                FarmNavigationView(manager: manager)
            }

            if manager.visibleFarms.isEmpty {
                ContentUnavailableView {
                    Label(loc("Keine Hauptfarm", "No main farm"), systemImage: "leaf")
                } description: {
                    Text(manager.hasSaveFolder
                         ? loc("Sobald ein gültiger Spielstand vorliegt, erscheinen deine Farmen hier.", "Your farms appear here when a valid save is available.")
                         : loc("Verbinde deinen FT2-Speicherort in den Einstellungen.", "Connect your FT2 storage folder in Settings."))
                }
            } else {
                // One shared wall-clock sample for all cards; no accumulated timer time.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = Date()
                    ScrollView {
                        if manager.catalog.effectiveViewMode == .overview {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                                ForEach(manager.visibleFarms) { farm in
                                    FarmCardView(farm: farm, state: manager.state(for: farm, at: now), compact: true)
                                }
                            }
                            .padding(20)
                        } else if let farm = manager.selectedFarm {
                            FarmCardView(farm: farm, state: manager.state(for: farm, at: now), compact: false)
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(loc("Jahreszeiten Tracker", "Season Tracker"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(loc("Einstellungen", "Settings"))
                .accessibilityLabel(loc("Einstellungen", "Settings"))
            }
        }
    }
}

// Native pickers own local selection state. Persist user changes through SwiftUI's
// change lifecycle instead of publishing the catalog from a control's Binding setter.
private struct FarmNavigationView: View {
    @ObservedObject var manager: FarmManager
    @State private var viewMode: FarmViewMode
    @State private var selectedFarmIdentity: FarmIdentity?

    init(manager: FarmManager) {
        self.manager = manager
        _viewMode = State(initialValue: manager.viewMode)
        _selectedFarmIdentity = State(initialValue: manager.selectedFarmIdentity)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(loc("Ansicht", "View"), selection: $viewMode) {
                    Text(loc("Einzelfarm", "Single farm")).tag(FarmViewMode.single)
                    Text(loc("Übersicht", "Overview")).tag(FarmViewMode.overview)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Spacer(minLength: 0)
            }
            .padding()
            if viewMode == .single {
                Picker(loc("Hauptfarm", "Main farm"), selection: $selectedFarmIdentity) {
                    ForEach(manager.visibleFarms) { farm in
                        Text(farm.displayName).tag(farm.identity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .onChange(of: viewMode) { _, value in manager.viewMode = value }
        .onChange(of: selectedFarmIdentity) { _, value in manager.selectedFarmIdentity = value }
        .onChange(of: manager.viewMode) { _, value in viewMode = value }
        .onChange(of: manager.selectedFarmIdentity) { _, value in selectedFarmIdentity = value }
    }
}
