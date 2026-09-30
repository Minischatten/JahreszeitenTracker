import Foundation
import Combine
import AppKit

struct FarmData: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var startSeason: Season = .spring
    var initialRemainingMinutes: Double = 17
    var absoluteStartTimeInterval: Double = 0
    var isTimerRunning = false
    // Optional additions keep savedFarmsData_v1 and existing manual references readable.
    var automaticReference: SaveReference?
    var automaticEnabled: Bool?
    var manualCorrection: Double?
    var sourceBookmark: Data?
    var sourceSlot: Int?
}

@MainActor
final class FarmManager: ObservableObject {
    @Published var farms: [FarmData] { didSet { saveFarms() } }
    @Published var selectedFarmIndex = 0
    @Published private var statuses: [Int: String] = [:]
    private let defaults: UserDefaults
    private let key = "savedFarmsData_v1"
    private var pollingTask: Task<Void, Never>?
    private var isScanning = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FarmData].self, from: data), decoded.count == 4 {
            farms = decoded
            for i in farms.indices {
                if let reference = farms[i].automaticReference,
                   (try? reference.validated(now: Date())) == nil {
                    farms[i].automaticReference = nil
                }
            }
        } else {
            farms = (0..<4).map { FarmData(id: $0, name: "Farm \($0 + 1)") }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanSources()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    var sourceSlot: Int { farms[selectedFarmIndex].sourceSlot ?? 0 }
    var hasSaveFolder: Bool { farms[selectedFarmIndex].sourceBookmark != nil }
    var syncStatus: String {
        statuses[selectedFarmIndex] ?? (hasSaveFolder
            ? loc("FT2: gespeicherte Referenz; Prüfung läuft", "FT2: saved reference; checking")
            : loc("Manuelle Synchronisation", "Manual synchronization"))
    }

    func state(at date: Date) -> SeasonState {
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
        panel.message = loc("Ordner mit farm_N_0.data bis farm_N_5.data auswählen. FT2-Dateien werden ausschließlich gelesen.",
                            "Select the folder containing farm_N_0.data to farm_N_5.data. FT2 files are read only.")
        let index = selectedFarmIndex
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            farms[index].sourceBookmark = bookmark
            statuses[index] = loc("FT2: Ordner ausgewählt", "FT2: folder selected")
            Task { await scanSources() }
        } catch { statuses[index] = error.localizedDescription }
    }

    func setSourceSlot(_ slot: Int) {
        guard (0..<4).contains(slot) else { return }
        farms[selectedFarmIndex].sourceSlot = slot
        Task { await scanSources() }
    }

    func disconnectSaveFolder() {
        farms[selectedFarmIndex].sourceBookmark = nil
        statuses[selectedFarmIndex] = loc("FT2 getrennt; letzte Referenz bleibt erhalten", "FT2 disconnected; last reference retained")
    }

    func startManually() {
        var farm = farms[selectedFarmIndex]
        farm.absoluteStartTimeInterval = Date().timeIntervalSince1970 - (1020 - farm.initialRemainingMinutes * 60)
        farm.automaticEnabled = false
        farm.isTimerRunning = true
        farms[selectedFarmIndex] = farm
        statuses[selectedFarmIndex] = loc("Manuell; neuerer FT2-Save synchronisiert erneut", "Manual; a newer FT2 save will synchronize again")
    }

    func adjustTime(by seconds: TimeInterval) {
        var farm = farms[selectedFarmIndex]
        if farm.automaticEnabled != false, farm.automaticReference != nil {
            farm.manualCorrection = (farm.manualCorrection ?? 0) + seconds
        } else { farm.absoluteStartTimeInterval += seconds }
        farms[selectedFarmIndex] = farm
    }

    func syncToCurrentSeasonStart() {
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

    private func saveFarms() {
        if let data = try? JSONEncoder().encode(farms) { defaults.set(data, forKey: key) }
    }

    private func scanSources() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        for index in farms.indices {
            guard let bookmark = farms[index].sourceBookmark else { continue }
            let slot = farms[index].sourceSlot ?? 0
            let result = await Task.detached(priority: .utility) {
                FT2SaveAccess.scan(bookmark: bookmark, slot: slot, now: Date())
            }.value
            // Folder/slot may have been changed or disconnected while reading.
            guard farms[index].sourceBookmark == bookmark, (farms[index].sourceSlot ?? 0) == slot else { continue }
            if let refreshed = result.refreshedBookmark { farms[index].sourceBookmark = refreshed }
            guard let reference = result.reference else {
                statuses[index] = loc("FT2: letzte Referenz bleibt erhalten — ", "FT2: last reference retained — ") + result.message
                continue
            }
            switch ReferenceUpdate.decision(candidate: reference, previous: farms[index].automaticReference) {
            case .older:
                statuses[index] = loc("FT2: älterer Save ignoriert", "FT2: older save ignored")
                continue
            case .conflict:
                statuses[index] = loc("FT2: widersprüchlicher Save ignoriert", "FT2: conflicting save ignored")
                continue
            case .unchanged:
                statuses[index] = loc("FT2: Referenz unverändert", "FT2: reference unchanged")
                continue
            case .accept: break
            }
            var farm = farms[index]
            farm.automaticReference = reference
            farm.automaticEnabled = true
            farm.manualCorrection = 0
            farm.isTimerRunning = true
            // Also populate the legacy reference as an independent manual fallback.
            farm.startSeason = Season.allCases[reference.seasonIndex]
            farm.absoluteStartTimeInterval = reference.savedAt.timeIntervalSince1970 + Double(reference.nextBoundary - reference.gameTime) - 1020
            farms[index] = farm
            statuses[index] = loc("FT2 synchronisiert: ", "FT2 synchronized: ") + reference.sourceName
        }
    }
}
