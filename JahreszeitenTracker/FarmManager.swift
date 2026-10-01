import Foundation
import Combine
import AppKit

@MainActor
final class FarmManager: ObservableObject {
    @Published var catalog: FarmCatalog { didSet { saveCatalog() } }
    @Published private var sourceStatus = ""
    @Published private(set) var saveFolderAvailable = false
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
    var settingsStatus: String {
        if !hasSaveFolder { return loc("Kein Spielstandordner ausgewählt", "No save folder selected") }
        return saveFolderAvailable ? loc("Spielstandordner verfügbar", "Save folder available")
            : loc("Spielstandordner derzeit nicht verfügbar", "Save folder currently unavailable")
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
        panel.message = loc("Wähle den Ordner aus, in dem Farm Together 2 deine Spielstände ablegt. Spielstände werden ausschließlich gelesen.",
                            "Select the folder where Farm Together 2 stores your saves. Saves are read only.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            saveFolderAvailable = false
            catalog.selectSource(path: folder.standardizedFileURL.path, bookmark: bookmark)
            sourceStatus = loc("FT2: Ordner ausgewählt; Prüfung läuft", "FT2: folder selected; checking")
            Task { await scanSources() }
        } catch { sourceStatus = error.localizedDescription }
    }

    func disconnectSaveFolder() {
        saveFolderAvailable = false
        catalog.activeSourceID = nil
        for i in catalog.farms.indices { catalog.farms[i].available = false }
        sourceStatus = loc("FT2 getrennt; Referenzen bleiben erhalten", "FT2 disconnected; references retained")
    }

    @discardableResult
    func moveFarm(_ identity: FarmIdentity, to target: FarmIdentity) -> Bool {
        guard visibleFarms.count > 1,
              visibleFarms.contains(where: { $0.identity == identity }),
              visibleFarms.contains(where: { $0.identity == target }) else { return false }
        var updated = catalog
        guard updated.moveFarm(identity, to: target) else { return false }
        catalog = updated
        return true
    }

    @discardableResult
    func removeInactiveFarm(identity: FarmIdentity) -> Bool {
        var updated = catalog
        guard updated.removeInactiveFarm(identity: identity) else { return false }
        catalog = updated
        return true
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
        saveFolderAvailable = result.readings != nil
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
