import Foundation
import Combine
import AppKit

@MainActor
final class FarmManager: ObservableObject {
    @Published var catalog: FarmCatalog { didSet { saveCatalog() } }
    @Published var selectedFarmIndex = 0 {
        didSet { catalog.selectedFarmID = farms.indices.contains(selectedFarmIndex) ? farms[selectedFarmIndex].id : nil }
    }
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
        if let id = catalog.selectedFarmID, let index = catalog.farms.firstIndex(where: { $0.id == id }) {
            selectedFarmIndex = index
        }
        saveCatalog()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanSources()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    var hasSaveFolder: Bool { catalog.activeSourceID != nil }
    var syncStatus: String {
        if !sourceStatus.isEmpty { return sourceStatus }
        guard farms.indices.contains(selectedFarmIndex) else {
            return loc("FT2-Speicherordner auswählen", "Select FT2 storage folder")
        }
        return farms[selectedFarmIndex].status ?? loc("FT2: gespeicherte Referenz; Prüfung läuft", "FT2: saved reference; checking")
    }
    func state(at date: Date) -> SeasonState {
        guard farms.indices.contains(selectedFarmIndex) else { return SeasonState(seasonIndex: 0, remaining: 1020) }
        let farm = farms[selectedFarmIndex]
        if farm.automaticEnabled != false, let reference = farm.automaticReference {
            return reference.state(at: date.addingTimeInterval(-(farm.manualCorrection ?? 0)))
        }
        let index = Season.allCases.firstIndex(of: farm.startSeason) ?? 0
        return SeasonCalculator.state(seasonIndex: index,
                                      seasonStart: Date(timeIntervalSince1970: farm.absoluteStartTimeInterval), at: date)
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

    func startManually() {
        guard farms.indices.contains(selectedFarmIndex) else { return }
        var farm = farms[selectedFarmIndex]
        farm.absoluteStartTimeInterval = Date().timeIntervalSince1970 - (1020 - farm.initialRemainingMinutes * 60)
        farm.automaticEnabled = false
        farm.isTimerRunning = true
        farms[selectedFarmIndex] = farm
        catalog.farms[selectedFarmIndex].status = loc("Manuell; neuerer FT2-Save synchronisiert erneut", "Manual; a newer FT2 save will synchronize again")
    }

    func adjustTime(by seconds: TimeInterval) {
        guard farms.indices.contains(selectedFarmIndex) else { return }
        var farm = farms[selectedFarmIndex]
        if farm.automaticEnabled != false, farm.automaticReference != nil {
            farm.manualCorrection = (farm.manualCorrection ?? 0) + seconds
        } else { farm.absoluteStartTimeInterval += seconds }
        farms[selectedFarmIndex] = farm
    }

    func syncToCurrentSeasonStart() {
        guard farms.indices.contains(selectedFarmIndex) else { return }
        let now = Date()
        let current = state(at: now)
        // Works at negative elapsed times too; retains the stored automatic high-water mark.
        var farm = farms[selectedFarmIndex]
        farm.startSeason = Season.allCases[current.seasonIndex]
        farm.absoluteStartTimeInterval = now.timeIntervalSince1970
        farm.automaticEnabled = false
        farm.manualCorrection = 0
        farms[selectedFarmIndex] = farm
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
        let selectedID = farms.indices.contains(selectedFarmIndex) ? farms[selectedFarmIndex].id : nil
        catalog.merge(readings, sourceID: sourceID)
        selectedFarmIndex = selectedID.flatMap { id in farms.firstIndex(where: { $0.id == id }) } ?? 0
    }
}
