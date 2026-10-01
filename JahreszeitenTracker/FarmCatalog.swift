import Foundation

nonisolated enum Season: String, CaseIterable, Identifiable, Codable {
    case spring, summer, autumn, winter
    var id: String { rawValue }
}

nonisolated struct FarmIdentity: Codable, Hashable, Sendable {
    let sourceID: UUID
    let slotIndex: Int
    let creationTime: Int64
}

// Dynamic FT2 farms retain their independent reference and manual controls.
nonisolated struct FarmData: Identifiable, Codable, Equatable, Sendable {
    var id: Int
    var name: String
    var startSeason: Season = .spring
    var initialRemainingMinutes: Double = 17
    var absoluteStartTimeInterval: Double = 0
    var isTimerRunning = false
    var automaticReference: SaveReference?
    var automaticEnabled: Bool?
    var manualCorrection: Double?
    var identity: FarmIdentity?
    var available: Bool?
    var status: String?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "FT2-Farm \(identity?.slotIndex.description ?? id.description)" : trimmed
    }
}

nonisolated struct TrackerSource: Codable, Equatable, Sendable {
    let id: UUID
    var path: String
    var bookmark: Data
}

nonisolated struct FarmReading: Sendable {
    let metadata: FT2FarmMetadata
    let reference: SaveReference?
    let message: String
}

nonisolated struct FarmCatalog: Codable, Sendable {
    var farms: [FarmData] = []
    var sources: [TrackerSource] = []
    var activeSourceID: UUID?
    var selectedFarmID: Int?

    static func restored(current: Data?, now: Date) -> FarmCatalog {
        if let current, var catalog = try? JSONDecoder().decode(FarmCatalog.self, from: current),
           Set(catalog.farms.map(\.id)).count == catalog.farms.count,
           catalog.farms.count <= 10_000,
           catalog.farms.allSatisfy({ $0.id >= 0 && $0.id < Int(Int32.max) && $0.identity != nil }),
           Set(catalog.farms.compactMap(\.identity)).count == catalog.farms.count,
           Set(catalog.sources.map(\.id)).count == catalog.sources.count {
            for i in catalog.farms.indices {
                if let reference = catalog.farms[i].automaticReference, (try? reference.validated(now: now)) == nil {
                    catalog.farms[i].automaticReference = nil
                    catalog.farms[i].isTimerRunning = false
                }
                catalog.farms[i].available = false
            }
            return catalog
        }
        return FarmCatalog()
    }

    mutating func selectSource(path: String, bookmark: Data) {
        if let index = sources.firstIndex(where: { $0.path == path }) {
            sources[index].bookmark = bookmark; activeSourceID = sources[index].id
        } else {
            let source = TrackerSource(id: UUID(), path: path, bookmark: bookmark)
            sources.append(source); activeSourceID = source.id
        }
        for i in farms.indices { farms[i].available = false }
    }

    mutating func merge(_ readings: [FarmReading], sourceID: UUID) {
        for i in farms.indices where farms[i].identity?.sourceID == sourceID {
            farms[i].available = false
            farms[i].status = "FT2: nicht registriert; letzte Referenz bleibt erhalten"
        }
        for reading in readings {
            let identity = FarmIdentity(sourceID: sourceID, slotIndex: reading.metadata.slotIndex,
                                        creationTime: reading.metadata.creationTime)
            let index: Int
            if let existing = farms.firstIndex(where: { $0.identity == identity }) { index = existing }
            else {
                let id = (farms.map(\.id).max() ?? -1) + 1
                farms.append(FarmData(id: id, name: reading.metadata.name, identity: identity))
                index = farms.count - 1
            }
            farms[index].name = reading.metadata.name
            farms[index].available = true
            guard let reference = reading.reference else {
                farms[index].status = "FT2: \(reading.message); letzte Referenz bleibt erhalten"
                continue
            }
            // Reused slots must not consume leftovers predating this incarnation.
            guard reference.savedTicks >= identity.creationTime else {
                farms[index].status = "FT2: Bereichsdatei älter als Farm-Erstellung"
                continue
            }
            switch ReferenceUpdate.decision(candidate: reference, previous: farms[index].automaticReference) {
            case .older: farms[index].status = "FT2: älterer Save ignoriert"
            case .conflict: farms[index].status = "FT2: widersprüchlicher Save ignoriert"
            case .unchanged: farms[index].status = "FT2: Referenz unverändert"
            case .accept:
                farms[index].automaticReference = reference
                farms[index].automaticEnabled = true
                farms[index].manualCorrection = 0
                farms[index].isTimerRunning = true
                farms[index].startSeason = Season.allCases[reference.seasonIndex]
                farms[index].absoluteStartTimeInterval = reference.savedAt.timeIntervalSince1970
                    + Double(reference.nextBoundary - reference.gameTime) - 1020
                farms[index].status = "FT2 synchronisiert: \(reference.sourceName)"
            }
        }
    }
}
