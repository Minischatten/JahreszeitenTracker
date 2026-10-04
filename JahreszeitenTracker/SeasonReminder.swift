import Foundation

nonisolated enum ReminderState: String, Codable, Sendable {
    case pending, expired, cancelled
}

nonisolated struct SeasonReminder: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let farmIdentity: FarmIdentity
    let seasonIndex: Int
    let createdAt: Date
    var scheduledAt: Date
    var reference: SaveReference
    var farmName: String
    var state: ReminderState
    var requestID: String { "season-reminder.\(id.uuidString)" }
}

nonisolated enum ReminderRules {
    static func canSchedule(_ farm: FarmData) -> Bool {
        guard farm.identity != nil, farm.registered == true,
              let reference = farm.automaticReference,
              FT2VersionPolicy.isConfirmed(reference.version),
              farm.compatibility?.hasRejectedVersion != true,
              (farm.compatibility?.unconfirmedVersions ?? []).isEmpty else { return false }
        return true
    }

    static func nextStart(reference: SaveReference, seasonIndex: Int, now: Date) -> Date {
        let state = reference.state(at: now)
        let distance = (seasonIndex - state.seasonIndex + 4) % 4
        let steps = distance == 0 ? 4 : distance
        return now.addingTimeInterval(state.remaining + Double(steps - 1) * SeasonCalculator.duration)
    }

    // Keep the originally selected occurrence, not a newly selected next cycle.
    static func correctedStart(_ reminder: SeasonReminder, reference: SaveReference) -> Date {
        let offset = (reminder.seasonIndex - reference.seasonIndex + 4) % 4
        let base = reference.savedAt.addingTimeInterval(
            Double(reference.nextBoundary - reference.gameTime) - SeasonCalculator.duration
            + Double(offset) * SeasonCalculator.duration)
        let cycle = SeasonCalculator.duration * 4
        let cycles = (reminder.scheduledAt.timeIntervalSince(base) / cycle).rounded()
        return base.addingTimeInterval(cycles * cycle)
    }
}
