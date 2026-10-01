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

// Farm identities and save references are independent of the presentation.
nonisolated struct FarmData: Identifiable, Codable, Equatable, Sendable {
    var id: Int
    var name: String
    var automaticReference: SaveReference?
    var identity: FarmIdentity?
    var available: Bool?
    var registered: Bool?
    var referenceVerified: Bool?
    var status: String?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "FT2-Farm" : trimmed
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
    var selectedFarmIdentity: FarmIdentity?
    var preferredViewMode: FarmViewMode = .single
    var displaySourceID: UUID?

    private enum CodingKeys: String, CodingKey {
        case farms, sources, activeSourceID, selectedFarmIdentity, preferredViewMode, displaySourceID
        case selectedFarmID // Read the existing selection once; never write this key again.
    }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        farms = try container.decode([FarmData].self, forKey: .farms)
        sources = try container.decode([TrackerSource].self, forKey: .sources)
        activeSourceID = try container.decodeIfPresent(UUID.self, forKey: .activeSourceID)
        selectedFarmIdentity = try container.decodeIfPresent(FarmIdentity.self, forKey: .selectedFarmIdentity)
        if selectedFarmIdentity == nil, let oldID = try container.decodeIfPresent(Int.self, forKey: .selectedFarmID) {
            selectedFarmIdentity = farms.first(where: { $0.id == oldID })?.identity
        }
        preferredViewMode = try container.decodeIfPresent(FarmViewMode.self, forKey: .preferredViewMode) ?? .single
        displaySourceID = try container.decodeIfPresent(UUID.self, forKey: .displaySourceID) ?? activeSourceID ?? sources.last?.id
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(farms, forKey: .farms)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(activeSourceID, forKey: .activeSourceID)
        try container.encodeIfPresent(selectedFarmIdentity, forKey: .selectedFarmIdentity)
        try container.encode(preferredViewMode, forKey: .preferredViewMode)
        try container.encodeIfPresent(displaySourceID, forKey: .displaySourceID)
    }
    var visibleFarms: [FarmData] {
        let sourceID = activeSourceID ?? displaySourceID
        return farms.filter { $0.identity?.sourceID == sourceID && $0.registered != false }
    }
    var effectiveViewMode: FarmViewMode { visibleFarms.count < 2 ? .single : preferredViewMode }

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
                }
                catalog.farms[i].available = false
                catalog.farms[i].referenceVerified = false
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
        displaySourceID = activeSourceID
        for i in farms.indices { farms[i].available = false; farms[i].referenceVerified = false }
    }

    mutating func merge(_ readings: [FarmReading], sourceID: UUID) {
        for i in farms.indices where farms[i].identity?.sourceID == sourceID {
            farms[i].available = false
            farms[i].registered = false
            farms[i].referenceVerified = false
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
            farms[index].registered = true
            farms[index].referenceVerified = false
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
            case .unchanged:
                farms[index].referenceVerified = true
                farms[index].status = "FT2: Referenz unverändert"
            case .accept:
                farms[index].automaticReference = reference
                farms[index].referenceVerified = true
                farms[index].status = "FT2 synchronisiert: \(reference.sourceName)"
            }
        }
    }
}

nonisolated enum FarmViewMode: String, Codable, CaseIterable {
    case single, overview
}

nonisolated enum FarmSyncState {
    case synchronized, lastStand, waiting
    static func forFarm(_ farm: FarmData) -> FarmSyncState {
        guard farm.automaticReference != nil else { return .waiting }
        return farm.available == true && farm.referenceVerified == true ? .synchronized : .lastStand
    }
}

nonisolated enum CountdownDisplay {
    static func seconds(remaining: TimeInterval) -> Int { Int(min(remaining + 2, 1020)) }
    static func text(remaining: TimeInterval) -> String {
        let seconds = seconds(remaining: remaining)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
