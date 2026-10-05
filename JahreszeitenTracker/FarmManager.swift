import Foundation
import Combine
import AppKit
import Darwin

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
    var knownFarms: [FarmData] { catalog.knownFarms }
    func visibleFarms(showHiddenFarms: Bool = false) -> [FarmData] {
        knownFarms.filter { showHiddenFarms || !$0.hidden }
    }
    var selectedFarm: FarmData? {
        knownFarms.first(where: { $0.identity == catalog.selectedFarmIdentity }) ?? knownFarms.first
    }
    var selectedFarmIdentity: FarmIdentity? {
        get { selectedFarm?.identity }
        set {
            guard let newValue,
                  knownFarms.contains(where: { $0.identity == newValue }),
                  newValue != selectedFarmIdentity else { return }
            catalog.selectedFarmIdentity = newValue
        }
    }
    var settingsStatus: String {
        if !hasSaveFolder { return String(localized: "Kein Spielstandordner ausgewählt") }
        return saveFolderAvailable ? String(localized: "Spielstandordner verfügbar")
            : String(localized: "Spielstandordner derzeit nicht verfügbar")
    }
    var catalogVersionNotice: String? {
        guard let source = catalog.sources.first(where: { $0.id == (catalog.activeSourceID ?? catalog.displaySourceID) }),
              let notice = source.metadataNotice else { return nil }
        if notice.rejected {
            return String(localized: "Spielstandversion \(String(notice.version)) konnte nicht sicher gelesen werden. Vorhandene Farmen und Referenzen bleiben erhalten.")
        }
        guard !FT2VersionPolicy.isConfirmed(notice.version) else { return nil }
        return String(localized: "Spielstandversion \(String(notice.version)) ist noch nicht bestätigt. Neue Farmen, Umbenennungen und Registrierungsänderungen werden erst nach Bestätigung übernommen.")
    }
    var sourcePath: String? { catalog.sources.first(where: { $0.id == catalog.activeSourceID })?.path }
    func state(for farm: FarmData, at date: Date) -> SeasonState? {
        farm.automaticReference?.state(at: date)
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.directoryURL = Self.saveFolderPanelStartURL()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Lesenden Zugriff erlauben")
        panel.message = String(localized: "Wähle den Ordner aus, in dem Farm Together 2 deine Spielstände ablegt. Spielstände werden ausschließlich gelesen.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            saveFolderAvailable = false
            catalog.selectSource(path: folder.standardizedFileURL.path, bookmark: bookmark)
            sourceStatus = "FT2: Ordner ausgewählt; Prüfung läuft"
            Task { await scanSources() }
        } catch { sourceStatus = error.localizedDescription }
    }

    static func saveFolderPanelStartURL(home: URL? = nil, fileManager: FileManager = .default) -> URL {
        // Foundation's home points into the sandbox; the account home is only
        // used to suggest a panel location, never to grant file access.
        let userHome = home ?? getpwuid(getuid()).map {
            URL(fileURLWithPath: String(cString: $0.pointee.pw_dir), isDirectory: true)
        } ?? fileManager.homeDirectoryForCurrentUser
        let storage = userHome.appendingPathComponent(
            "Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: storage.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return userHome }
        return storage
    }

    func disconnectSaveFolder() {
        saveFolderAvailable = false
        catalog.activeSourceID = nil
        for i in catalog.farms.indices { catalog.farms[i].available = false }
        sourceStatus = "FT2 getrennt; Referenzen bleiben erhalten"
    }

    @discardableResult
    func setHidden(_ hidden: Bool, identity: FarmIdentity) -> Bool {
        guard let index = catalog.farms.firstIndex(where: { $0.identity == identity }),
              catalog.farms[index].hidden != hidden else { return false }
        catalog.farms[index].hidden = hidden
        return true
    }

    @discardableResult
    func moveFarm(_ identity: FarmIdentity, to target: FarmIdentity, showHiddenFarms: Bool = false) -> Bool {
        let visibleFarms = visibleFarms(showHiddenFarms: showHiddenFarms)
        guard visibleFarms.count > 1,
              visibleFarms.contains(where: { $0.identity == identity }),
              visibleFarms.contains(where: { $0.identity == target }) else { return false }
        var updated = catalog
        guard updated.moveFarm(identity, to: target, includingHidden: showHiddenFarms) else { return false }
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
            catalog.apply(result, sourceID: sourceID)
            sourceStatus = "FT2: Referenzen bleiben erhalten — " + result.message
            return
        }
        sourceStatus = readings.isEmpty ? "FT2: keine Hauptfarm registriert" : ""
        catalog.apply(result, sourceID: sourceID)
        if !knownFarms.contains(where: { $0.identity == catalog.selectedFarmIdentity }) {
            catalog.selectedFarmIdentity = knownFarms.first?.identity
        }
    }
}
