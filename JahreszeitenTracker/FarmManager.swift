import Foundation
import Combine
import AppKit

@MainActor
final class FarmManager: ObservableObject {
    @Published var catalog: FarmCatalog { didSet { saveCatalog() } }
    @Published private var sourceStatus = ""
    private let defaults: UserDefaults
    private let key = "ft2FarmCatalog_v2"
    private var pollingTask: Task<Void, Never>?
    private var isScanning = false

    var farms: [FarmData] {
        get { catalog.farms }
        set { catalog.farms = newValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        catalog = FarmCatalog.restored(current: defaults.data(forKey: key), now: Date())
        saveCatalog()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanSources()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    var hasSaveFolder: Bool { catalog.activeSourceID != nil }
    var visibleFarms: [FarmData] { catalog.visibleFarms }
    var selectedFarm: FarmData? {
        visibleFarms.first(where: { $0.identity == catalog.selectedFarmIdentity }) ?? visibleFarms.first
    }
    var selectedFarmIdentity: FarmIdentity? {
        get { selectedFarm?.identity }
        set {
            guard let newValue,
                  visibleFarms.contains(where: { $0.identity == newValue }),
                  newValue != selectedFarmIdentity else { return }
            catalog.selectedFarmIdentity = newValue
        }
    }
    var viewMode: FarmViewMode {
        get { catalog.preferredViewMode }
        set {
            guard newValue != catalog.preferredViewMode else { return }
            catalog.preferredViewMode = newValue
        }
    }
    var settingsStatus: String {
        if !sourceStatus.isEmpty { return sourceStatus }
        return hasSaveFolder ? loc("Der Speicherort wird automatisch geprüft.", "The storage folder is checked automatically.")
            : loc("Kein Speicherort verbunden. Vorhandene Referenzen bleiben erhalten.", "No storage folder connected. Existing references are retained.")
    }
    var sourcePath: String? { catalog.sources.first(where: { $0.id == catalog.activeSourceID })?.path }
    func state(for farm: FarmData, at date: Date) -> SeasonState? {
        farm.automaticReference?.state(at: date)
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc("Lesenden Zugriff erlauben", "Allow read access")
        panel.message = loc("Übergeordneten Ordner mit farms.mlk und farms/ auswählen. FT2-Dateien werden ausschließlich gelesen.",
                            "Select the parent folder containing farms.mlk and farms/. FT2 files are read only.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            catalog.selectSource(path: folder.standardizedFileURL.path, bookmark: bookmark)
            sourceStatus = loc("FT2: Ordner ausgewählt; Prüfung läuft", "FT2: folder selected; checking")
            Task { await scanSources() }
        } catch { sourceStatus = error.localizedDescription }
    }

    func disconnectSaveFolder() {
        catalog.activeSourceID = nil
        for i in catalog.farms.indices { catalog.farms[i].available = false }
        sourceStatus = loc("FT2 getrennt; Referenzen bleiben erhalten", "FT2 disconnected; references retained")
    }

    private func saveCatalog() {
        if let data = try? JSONEncoder().encode(catalog) { defaults.set(data, forKey: key) }
    }

    private func scanSources() async {
        guard !isScanning, let sourceID = catalog.activeSourceID,
              let source = catalog.sources.first(where: { $0.id == sourceID }) else { return }
        isScanning = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .utility) {
            FT2SaveAccess.scanCatalog(bookmark: source.bookmark, now: Date())
        }.value
        guard catalog.activeSourceID == sourceID,
              catalog.sources.first(where: { $0.id == sourceID })?.bookmark == source.bookmark else { return }
        if let refreshed = result.refreshedBookmark,
           let index = catalog.sources.firstIndex(where: { $0.id == sourceID }) {
            catalog.sources[index].bookmark = refreshed
        }
        guard let readings = result.readings else {
            for i in catalog.farms.indices where catalog.farms[i].identity?.sourceID == sourceID {
                catalog.farms[i].available = false
            }
            sourceStatus = loc("FT2: Referenzen bleiben erhalten — ", "FT2: references retained — ") + result.message
            return
        }
        sourceStatus = readings.isEmpty ? loc("FT2: keine Hauptfarm registriert", "FT2: no main farm registered") : ""
        catalog.merge(readings, sourceID: sourceID)
        if !visibleFarms.contains(where: { $0.identity == catalog.selectedFarmIdentity }) {
            catalog.selectedFarmIdentity = visibleFarms.first?.identity
        }
    }
}
