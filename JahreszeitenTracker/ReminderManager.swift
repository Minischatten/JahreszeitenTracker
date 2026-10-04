import Foundation
import Combine

@MainActor
protocol ReminderNotifications: AnyObject {
    func authorize() async throws -> Bool
    func schedule(_ reminder: SeasonReminder) async throws
    func remove(_ requestIDs: [String])
    func pendingIDs() async -> Set<String>
}

@MainActor
final class ReminderManager: ObservableObject {
    @Published private(set) var reminders: [SeasonReminder]
    @Published private(set) var busy = false
    @Published private(set) var restoring = false
    @Published var errorMessage: String?
    private let service: any ReminderNotifications
    private let defaults: UserDefaults
    private let key = "seasonReminders_v1"
    private let clock: () -> Date
    private var observation: AnyCancellable?
    private var farms: [FarmData] = []
    private var reconcileRequested = false

    init(service: any ReminderNotifications, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init) {
        self.service = service; self.defaults = defaults; self.clock = clock
        reminders = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SeasonReminder].self, from: $0) } ?? []
    }

    func bind(to manager: FarmManager) {
        restoring = true
        farms = manager.catalog.farms
        observation = manager.$catalog.dropFirst().sink { [weak self] catalog in
            MainActor.assumeIsolated { self?.updateFarms(catalog.farms) }
        }
        Task {
            await restoreSystemRequests()
            restoring = false
            await reconcile()
        }
    }

    func active(for identity: FarmIdentity?, at now: Date = Date()) -> SeasonReminder? {
        reminders.first { $0.farmIdentity == identity && $0.state == .pending && $0.scheduledAt > now }
    }

    func setReminder(for farm: FarmData, seasonIndex: Int) async {
        guard !busy, !restoring, (0..<4).contains(seasonIndex), ReminderRules.canSchedule(farm),
              let identity = farm.identity else { return }
        busy = true; errorMessage = nil
        defer { finishOperation() }
        do {
            guard try await service.authorize() else {
                errorMessage = String(localized: "Mitteilungen sind nicht erlaubt. Du kannst sie in den macOS-Systemeinstellungen aktivieren.")
                return
            }
            // Permission UI may take time. Use the most recently read farm, not a stale copy.
            guard let current = farms.first(where: { $0.identity == identity }),
                  ReminderRules.canSchedule(current), let reference = current.automaticReference else {
                errorMessage = String(localized: "Für diese Farm liegt kein bestätigter Spielstand für eine Erinnerung vor.")
                return
            }
            let now = clock()
            let reminder = SeasonReminder(id: UUID(), farmIdentity: identity, seasonIndex: seasonIndex,
                createdAt: now, scheduledAt: ReminderRules.nextStart(reference: reference, seasonIndex: seasonIndex, now: now),
                reference: reference, farmName: current.displayName, state: .pending)
            try await service.schedule(reminder)
            guard farms.contains(where: { $0.identity == identity && !$0.isInactive }) else {
                service.remove([reminder.requestID])
                errorMessage = String(localized: "Für diese Farm liegt kein bestätigter Spielstand für eine Erinnerung vor.")
                return
            }
            let old = reminders.filter { $0.farmIdentity == identity }
            service.remove(old.map(\.requestID))
            reminders.removeAll { $0.farmIdentity == identity }
            reminders.append(reminder); persist()
        } catch {
            errorMessage = String(localized: "Die Erinnerung konnte nicht geplant werden. Bitte versuche es erneut.")
        }
    }

    func cancel(identity: FarmIdentity) {
        guard !busy, !restoring else { return }
        service.remove(reminders.filter { $0.farmIdentity == identity }.map(\.requestID))
        reminders.removeAll { $0.farmIdentity == identity }; persist()
    }

    func updateFarms(_ farms: [FarmData]) {
        self.farms = farms
        reconcileRequested = true
        guard !busy, !restoring else { return }
        Task { await reconcile() }
    }

    private func finishOperation() {
        busy = false
        if reconcileRequested && !restoring { Task { await reconcile() } }
    }

    func reconcile() async {
        guard !busy, !restoring else { reconcileRequested = true; return }
        busy = true; reconcileRequested = false
        defer { finishOperation() }
        let now = clock()
        for original in reminders {
            guard let index = reminders.firstIndex(where: { $0.id == original.id }) else { continue }
            guard let farm = farms.first(where: { $0.identity == original.farmIdentity }) else {
                service.remove([original.requestID]); reminders.remove(at: index); continue
            }
            guard original.state == .pending else { continue }
            if farm.isInactive {
                service.remove([original.requestID]); reminders[index].state = .cancelled; continue
            }
            if original.scheduledAt <= now {
                // The system may already have delivered it. Never plan the following cycle.
                reminders[index].state = .expired; continue
            }
            guard ReminderRules.canSchedule(farm), let reference = farm.automaticReference else { continue }
            var updated = original
            updated.farmName = farm.displayName
            if ReferenceUpdate.decision(candidate: reference, previous: original.reference) == .accept {
                updated.scheduledAt = ReminderRules.correctedStart(original, reference: reference)
                updated.reference = reference
            }
            if updated.scheduledAt <= now {
                service.remove([original.requestID]); updated.state = .expired
            } else if abs(updated.scheduledAt.timeIntervalSince(original.scheduledAt)) > 0.000001 || updated.farmName != original.farmName {
                do { try await service.schedule(updated) }
                catch {
                    errorMessage = String(localized: "Die Erinnerung konnte nicht aktualisiert werden. Der bisherige Termin bleibt bestehen.")
                    continue
                }
            }
            reminders[index] = updated
        }
        persist()
    }

    func restoreSystemRequests() async {
        guard !busy else { return }
        busy = true
        defer { finishOperation() }
        let pending = await service.pendingIDs()
        let now = clock()
        for index in reminders.indices where reminders[index].state == .pending {
            if reminders[index].scheduledAt <= now { reminders[index].state = .expired }
            else if !pending.contains(reminders[index].requestID) {
                // Missing request is not evidence of delivery. Do not silently re-arm it.
                reminders[index].state = .cancelled
            }
        }
        let known = Set(reminders.filter { $0.state == .pending }.map(\.requestID))
        service.remove(pending.filter { $0.hasPrefix("season-reminder.") && !known.contains($0) }.map { $0 })
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) { defaults.set(data, forKey: key) }
    }
}
