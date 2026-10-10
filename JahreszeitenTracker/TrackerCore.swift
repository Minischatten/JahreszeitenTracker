import Foundation

// No UI, timers or storage: all calculations receive their clock explicitly.
nonisolated enum TrackerClock {
    static let ticksAtUnixEpoch: Int64 = 621_355_968_000_000_000
    static func date(ticks: Int64) throws -> Date {
        guard ticks >= ticksAtUnixEpoch, ticks <= 3_155_378_975_999_999_999 else {
            throw FT2Error.invalid("Speicherzeitpunkt")
        }
        // Observed saves match UTC. DateTime.Kind is not present in these bytes.
        return Date(timeIntervalSince1970: Double(ticks - ticksAtUnixEpoch) / 10_000_000)
    }
}

/// Central, explicitly tested versions. Newer versions are only structurally probed.
nonisolated enum FT2VersionPolicy {
    static let confirmed: Set<Int> = [347, 350]
    static func isConfirmed(_ version: Int) -> Bool { confirmed.contains(version) }
    static func mayRead(_ version: Int) -> Bool { isConfirmed(version) || version > 347 }
}

nonisolated struct FT2VersionError: Error, LocalizedError {
    let version: Int?
    let reason: String
    var errorDescription: String? { reason }
}

nonisolated struct FarmCompatibility: Codable, Equatable, Sendable {
    var metadataVersion: Int? = nil
    var observedPlotVersion: Int? = nil
    var rejectedVersions: [Int] = []
    var metadataRejected = false

    var hasRejectedVersion: Bool { !rejectedVersions.isEmpty || metadataRejected }
    var unconfirmedVersions: [Int] { versionsUnconfirmed(by: FT2VersionPolicy.confirmed) }
    func versionsUnconfirmed(by confirmedVersions: Set<Int>) -> [Int] {
        Array(Set(([metadataVersion, observedPlotVersion].compactMap { $0 } + rejectedVersions)
            .filter { !confirmedVersions.contains($0) })).sorted()
    }
}

nonisolated struct MetadataNotice: Codable, Equatable, Sendable {
    let version: Int
    let rejected: Bool
    let deferredFarms: Int
}

nonisolated struct SaveReference: Codable, Equatable, Sendable {
    let gameTime: Int64
    let savedTicks: Int64
    let nextBoundary: Int64
    let seasonIndex: Int
    let sourceName: String
    let saveVersion: Int?
    var version: Int { saveVersion ?? 347 }

    init(gameTime: Int64, savedTicks: Int64, nextBoundary: Int64, seasonIndex: Int,
         sourceName: String, saveVersion: Int? = nil) {
        self.gameTime = gameTime; self.savedTicks = savedTicks; self.nextBoundary = nextBoundary
        self.seasonIndex = seasonIndex; self.sourceName = sourceName; self.saveVersion = saveVersion
    }

    func validated(now: Date) throws -> SaveReference {
        let saved = try TrackerClock.date(ticks: savedTicks)
        guard gameTime >= 0, gameTime < 9_000_000_000_000,
              nextBoundary > gameTime, nextBoundary - gameTime <= 1020,
              (0..<4).contains(seasonIndex), saved <= now.addingTimeInterval(300) else {
            throw FT2Error.invalid("Zeit- oder Saisonwerte")
        }
        return self
    }

    var savedAt: Date { // Validated before use or after decoding persistence.
        Date(timeIntervalSince1970: Double(savedTicks - TrackerClock.ticksAtUnixEpoch) / 10_000_000)
    }

    func state(at now: Date) -> SeasonState {
        SeasonCalculator.state(seasonIndex: seasonIndex,
                               seasonStart: savedAt.addingTimeInterval(Double(nextBoundary - gameTime) - 1020),
                               at: now)
    }
}

nonisolated struct SeasonState: Equatable, Sendable {
    let seasonIndex: Int
    let remaining: TimeInterval
}

nonisolated enum SeasonCalculator {
    static let duration: TimeInterval = 1020
    static func state(seasonIndex: Int, seasonStart: Date, at now: Date) -> SeasonState {
        let elapsed = now.timeIntervalSince(seasonStart)
        let remainder = elapsed.truncatingRemainder(dividingBy: duration * 4)
        let phase = remainder < 0 ? remainder + duration * 4 : remainder
        return SeasonState(seasonIndex: (seasonIndex + Int(phase / duration)) % 4,
                           remaining: duration - phase.truncatingRemainder(dividingBy: duration))
    }
}

nonisolated enum FT2Error: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return "FT2-Save abgelehnt: \(reason)" }
    }
}

nonisolated enum ReferenceUpdate: Equatable {
    case accept, unchanged, older, conflict
    static func decision(candidate: SaveReference, previous: SaveReference?) -> ReferenceUpdate {
        guard let previous else { return .accept }
        if candidate.savedTicks < previous.savedTicks { return .older }
        if candidate.savedTicks > previous.savedTicks { return .accept }
        return candidate.gameTime == previous.gameTime && candidate.nextBoundary == previous.nextBoundary
            && candidate.seasonIndex == previous.seasonIndex ? .unchanged : .conflict
    }
}
