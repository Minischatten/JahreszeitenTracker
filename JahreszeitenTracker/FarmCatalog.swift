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
    var compatibility: FarmCompatibility?
    var hidden = false

    var isInactive: Bool { registered == false }

    func versionExplanation() -> String? {
        let state = FarmSyncState.forFarm(self)
        guard [.unconfirmedVersion, .lastStandNewVersion, .waitingNewVersion].contains(state) else { return nil }
        let versions = Array(Set((compatibility?.unconfirmedVersions ?? [])
            + (compatibility?.rejectedVersions ?? [])
            + (compatibility?.metadataRejected == true ? [compatibility?.metadataVersion].compactMap { $0 } : [])
            + (automaticReference.map { FT2VersionPolicy.isConfirmed($0.version) ? [] : [$0.version] } ?? []))).sorted()
        let numbers = versions.map(String.init).joined(separator: ", ")
        if compatibility?.hasRejectedVersion == true {
            if automaticReference == nil {
                return String(localized: "Farm Together 2 verwendet Spielstandversion \(numbers). Die benötigten Daten konnten nicht sicher gelesen werden. Es liegt noch kein gültiger Spielstand für einen Countdown vor.")
            }
            return String(localized: "Farm Together 2 verwendet Spielstandversion \(numbers). Die benötigten Daten konnten nicht sicher gelesen werden. Der Countdown verwendet den zuletzt gültigen Spielstand.")
        }
        if automaticReference == nil {
            return String(localized: "Farm Together 2 verwendet Spielstandversion \(numbers). Der JahreszeitenTracker konnte die benötigten Daten weiterhin lesen, diese Version wurde jedoch noch nicht bestätigt. Es liegt noch kein gültiger Spielstand für einen Countdown vor.")
        }
        return String(localized: "Farm Together 2 verwendet Spielstandversion \(numbers). Der JahreszeitenTracker konnte die benötigten Daten weiterhin lesen, diese Version wurde jedoch noch nicht bestätigt.")
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "FT2-Farm") : trimmed
    }
}

extension FarmData {
    private nonisolated enum CodingKeys: String, CodingKey {
        case id, name, automaticReference, identity, available, registered, referenceVerified, status, compatibility, hidden
    }
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        automaticReference = try values.decodeIfPresent(SaveReference.self, forKey: .automaticReference)
        identity = try values.decodeIfPresent(FarmIdentity.self, forKey: .identity)
        available = try values.decodeIfPresent(Bool.self, forKey: .available)
        registered = try values.decodeIfPresent(Bool.self, forKey: .registered)
        referenceVerified = try values.decodeIfPresent(Bool.self, forKey: .referenceVerified)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        compatibility = try values.decodeIfPresent(FarmCompatibility.self, forKey: .compatibility)
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

nonisolated struct TrackerSource: Codable, Equatable, Sendable {
    let id: UUID
    var path: String
    var bookmark: Data
    var metadataNotice: MetadataNotice? = nil
}

nonisolated struct FarmReading: Sendable {
    let metadata: FT2FarmMetadata
    let reference: SaveReference?
    let message: String
    var rejectedVersions: [Int] = []
    var observedPlotVersion: Int? = nil
}

nonisolated struct FarmCatalog: Codable, Sendable {
    var farms: [FarmData] = []
    var sources: [TrackerSource] = []
    var activeSourceID: UUID?
    var selectedFarmIdentity: FarmIdentity?
    var displaySourceID: UUID?

    private enum CodingKeys: String, CodingKey {
        case farms, sources, activeSourceID, selectedFarmIdentity, displaySourceID
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
        displaySourceID = try container.decodeIfPresent(UUID.self, forKey: .displaySourceID) ?? activeSourceID ?? sources.last?.id
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(farms, forKey: .farms)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(activeSourceID, forKey: .activeSourceID)
        try container.encodeIfPresent(selectedFarmIdentity, forKey: .selectedFarmIdentity)
        try container.encodeIfPresent(displaySourceID, forKey: .displaySourceID)
    }
    var knownFarms: [FarmData] {
        let sourceID = activeSourceID ?? displaySourceID
        return farms.filter { $0.identity?.sourceID == sourceID }
    }
    // Existing catalog clients refer to source membership, never a UI filter.
    var visibleFarms: [FarmData] { knownFarms }

    /// Move to the target card's position, preserving every record and other sources.
    @discardableResult
    mutating func moveFarm(_ identity: FarmIdentity, to target: FarmIdentity, includingHidden: Bool = true) -> Bool {
        guard identity != target, identity.sourceID == target.sourceID else { return false }
        let positions = farms.indices.filter {
            farms[$0].identity?.sourceID == identity.sourceID && (includingHidden || !farms[$0].hidden)
        }
        var ordered = positions.map { farms[$0] }
        guard let from = ordered.firstIndex(where: { $0.identity == identity }),
              let to = ordered.firstIndex(where: { $0.identity == target }) else { return false }
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: to)
        for (position, farm) in zip(positions, ordered) { farms[position] = farm }
        return true
    }

    /// Removes only a confirmed, no-longer-registered tracker record.
    /// Full identity prevents removal of a new farm reusing the same slot.
    @discardableResult
    mutating func removeInactiveFarm(identity: FarmIdentity) -> Bool {
        guard let index = farms.firstIndex(where: { $0.identity == identity }),
              farms[index].isInactive else { return false }
        farms.remove(at: index)
        if selectedFarmIdentity == identity { selectedFarmIdentity = nil }
        return true
    }

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

    /// Parse failure never acts as an empty authoritative registry.
    mutating func apply(_ result: CatalogScanResult, sourceID: UUID, confirmedVersions: Set<Int> = FT2VersionPolicy.confirmed) {
        guard let readings = result.readings else {
            for i in farms.indices where farms[i].identity?.sourceID == sourceID {
                farms[i].available = false
                if result.metadataRejected, let version = result.metadataVersion {
                    var compatibility = farms[i].compatibility ?? FarmCompatibility()
                    compatibility.metadataVersion = version
                    compatibility.metadataRejected = true
                    farms[i].compatibility = compatibility
                }
            }
            if result.metadataRejected, let version = result.metadataVersion,
               let index = sources.firstIndex(where: { $0.id == sourceID }) {
                sources[index].metadataNotice = MetadataNotice(version: version, rejected: true, deferredFarms: 0)
            }
            return
        }
        merge(readings, sourceID: sourceID, metadataVersion: result.metadataVersion ?? 347, confirmedVersions: confirmedVersions)
    }

    mutating func merge(_ readings: [FarmReading], sourceID: UUID, metadataVersion: Int = 347, confirmedVersions: Set<Int> = FT2VersionPolicy.confirmed) {
        let authoritative = confirmedVersions.contains(metadataVersion)
        if let index = sources.firstIndex(where: { $0.id == sourceID }) {
            let deferred = authoritative ? 0 : readings.filter { reading in
                let identity = FarmIdentity(sourceID: sourceID, slotIndex: reading.metadata.slotIndex,
                                            creationTime: reading.metadata.creationTime)
                return !farms.contains { $0.identity == identity && $0.registered == true }
            }.count
            sources[index].metadataNotice = authoritative ? nil : MetadataNotice(version: metadataVersion, rejected: false, deferredFarms: deferred)
        }
        for i in farms.indices where farms[i].identity?.sourceID == sourceID {
            farms[i].available = false
            if authoritative { farms[i].registered = false }
            farms[i].referenceVerified = false
            if authoritative {
                farms[i].compatibility = FarmCompatibility(metadataVersion: metadataVersion)
            } else {
                // Absence from a non-authoritative registry does not constitute
                // a fresh plot check and must not erase an earlier plot warning.
                var compatibility = farms[i].compatibility ?? FarmCompatibility()
                compatibility.metadataVersion = metadataVersion
                compatibility.metadataRejected = false
                farms[i].compatibility = compatibility
            }
            farms[i].status = authoritative ? "FT2: nicht registriert; letzte Referenz bleibt erhalten" : "FT2: unbestätigter Katalog; Registrierung unverändert"
        }
        for reading in readings {
            let identity = FarmIdentity(sourceID: sourceID, slotIndex: reading.metadata.slotIndex,
                                        creationTime: reading.metadata.creationTime)
            let index: Int
            if let existing = farms.firstIndex(where: { $0.identity == identity }) {
                guard authoritative || farms[existing].registered == true else { continue }
                index = existing
            } else {
                guard authoritative else { continue }
                let id = (farms.map(\.id).max() ?? -1) + 1
                farms.append(FarmData(id: id, name: reading.metadata.name, identity: identity))
                index = farms.count - 1
            }
            if authoritative { farms[index].name = reading.metadata.name }
            farms[index].available = true
            farms[index].registered = true
            farms[index].referenceVerified = false
            farms[index].compatibility = FarmCompatibility(metadataVersion: metadataVersion,
                observedPlotVersion: reading.observedPlotVersion ?? reading.reference?.version,
                rejectedVersions: reading.rejectedVersions)
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
            case .conflict:
                if reference.version > 347 {
                    var compatibility = farms[index].compatibility ?? FarmCompatibility()
                    compatibility.rejectedVersions = Array(Set(compatibility.rejectedVersions + [reference.version])).sorted()
                    farms[index].compatibility = compatibility
                }
                farms[index].status = "FT2: widersprüchlicher Save ignoriert"
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

// Navigation is transient UI state; persisted identities remain in the catalog.
nonisolated struct FarmNavigation {
    var openedIdentity: FarmIdentity?
    var showsOverview = false
    func detail(in farms: [FarmData], knownFarms: [FarmData]? = nil,
                routingFarms: [FarmData]? = nil) -> FarmData? {
        if let openedIdentity {
            return (routingFarms ?? knownFarms ?? farms).first { $0.identity == openedIdentity }
        }
        guard !showsOverview else { return nil }
        // Filtering must not turn a multi-farm catalog into automatic detail.
        // Explicit reminder routing may also resolve farms from another source.
        if (knownFarms ?? farms).count == 1 && farms.count == 1 { return farms.first }
        return nil
    }
    func shouldSuppressInitialControlFocus(in farms: [FarmData], knownFarms: [FarmData],
                                           routingFarms: [FarmData]? = nil) -> Bool {
        // Overview cards must not receive automatic focus, even with one card.
        !farms.isEmpty && detail(in: farms, knownFarms: knownFarms, routingFarms: routingFarms) == nil
    }
    mutating func open(_ identity: FarmIdentity) { openedIdentity = identity; showsOverview = false }
    mutating func back() { openedIdentity = nil; showsOverview = true }
    mutating func reset() { openedIdentity = nil; showsOverview = false }
}

nonisolated enum FarmSyncState {
    case synchronized, lastStand, waiting, notFound, unconfirmedVersion, lastStandNewVersion, waitingNewVersion
    static func forFarm(_ farm: FarmData, confirmedVersions: Set<Int> = FT2VersionPolicy.confirmed) -> FarmSyncState {
        if farm.isInactive { return .notFound }
        if farm.compatibility?.hasRejectedVersion == true {
            return farm.automaticReference == nil ? .waitingNewVersion : .lastStandNewVersion
        }
        let referenceUnconfirmed = farm.automaticReference.map { !confirmedVersions.contains($0.version) } ?? false
        if referenceUnconfirmed || !(farm.compatibility?.versionsUnconfirmed(by: confirmedVersions).isEmpty ?? true) {
            return .unconfirmedVersion
        }
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
