import Foundation
import Combine

@MainActor
final class FakeNotifications: ReminderNotifications {
    var allowed = true
    var fail = false
    var authorizationCalls = 0
    var scheduled: [SeasonReminder] = []
    var pending: Set<String> = []
    var removed: [String] = []
    func authorize() async throws -> Bool { authorizationCalls += 1; return allowed }
    func schedule(_ reminder: SeasonReminder) async throws {
        if fail { throw FT2Error.invalid("synthetic") }
        scheduled.append(reminder); pending.insert(reminder.requestID)
    }
    func remove(_ requestIDs: [String]) { removed += requestIDs; pending.subtract(requestIDs) }
    func pendingIDs() async -> Set<String> { pending }
}

@main @MainActor
struct ReminderTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1; precondition(condition, message)
    }
    static func main() async {
        let suite = "ReminderTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let source = UUID()
        let identity = FarmIdentity(sourceID: source, slotIndex: 16, creationTime: 1234)
        func reference(_ season: Int, saved: Date? = nil, remaining: Int64 = 600, version: Int = 347) -> SaveReference {
            let saved = saved ?? now
            return SaveReference(gameTime: 1000, savedTicks: TrackerClock.ticksAtUnixEpoch + Int64(saved.timeIntervalSince1970 * 10_000_000),
                                 nextBoundary: 1000 + remaining, seasonIndex: season, sourceName: "synthetic", saveVersion: version)
        }
        for current in 0..<4 {
            for desired in 0..<4 {
                let ref = reference(current)
                let delta = (desired - current + 4) % 4
                let expected = 600 + Double((delta == 0 ? 4 : delta) - 1) * 1020
                check(ReminderRules.nextStart(reference: ref, seasonIndex: desired, now: now).timeIntervalSince(now) == expected,
                      "all season pairs use unadjusted reference")
            }
            let ref = reference(current, remaining: 1020)
            check(ReminderRules.nextStart(reference: ref, seasonIndex: current, now: now).timeIntervalSince(now) == 4080,
                  "same season at exact boundary waits full cycle")
            let boundary = now.addingTimeInterval(1020)
            let next = (current + 1) % 4
            check(ref.state(at: boundary).seasonIndex == next, "exact boundary agrees with existing calculator")
            check(ReminderRules.nextStart(reference: ref, seasonIndex: next, now: boundary).timeIntervalSince(boundary) == 4080,
                  "newly started selected season waits next occurrence")
            let later = now.addingTimeInterval(4080 * 100 + 123)
            check(ReminderRules.nextStart(reference: ref, seasonIndex: current, now: later).timeIntervalSince(later) == 4080 - 123,
                  "old reference extrapolates many cycles")
        }
        var farm = FarmData(id: 1, name: "Café %@ Farm", automaticReference: reference(0), identity: identity,
                            available: true, registered: true, referenceVerified: true)
        let service = FakeNotifications()
        let manager = ReminderManager(service: service, defaults: defaults, clock: { now })
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.authorizationCalls == 0, "no permission prompt at startup")
        await manager.setReminder(for: farm, seasonIndex: 1)
        check(manager.active(for: identity, at: now) != nil && service.scheduled.count == 1, "successful one-shot scheduling")
        let initial = manager.reminders[0]
        check(initial.scheduledAt == now.addingTimeInterval(600), "no +2 display correction in scheduled date")
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.scheduled.count == 1, "unchanged scan never reschedules")
        farm.hidden = true
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.scheduled.count == 1 && manager.active(for: identity, at: now) != nil, "hidden retains reminder")
        farm.name = "Renamed"
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.scheduled.count == 2 && service.scheduled.last?.id == initial.id && service.scheduled.last?.farmName == "Renamed", "rename same request")
        farm.automaticReference = reference(0, saved: now.addingTimeInterval(10), remaining: 590)
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.scheduled.count == 2, "new save with unchanged boundary does not reschedule")
        farm.automaticReference = reference(0, saved: now.addingTimeInterval(20), remaining: 585)
        manager.updateFarms([farm]); await manager.reconcile()
        check(service.scheduled.count == 3 && service.scheduled.last?.requestID == initial.requestID
              && manager.reminders[0].scheduledAt == now.addingTimeInterval(605), "corrected boundary retains request identity")
        farm.available = false
        manager.updateFarms([farm]); await manager.reconcile()
        check(manager.active(for: identity, at: now) != nil && service.scheduled.count == 3, "unavailable folder retains confirmed reference reminder")
        var unconfirmed = farm
        unconfirmed.automaticReference = reference(0, saved: now.addingTimeInterval(30), remaining: 800, version: 348)
        manager.updateFarms([unconfirmed]); await manager.reconcile()
        check(service.scheduled.count == 3, "unconfirmed save never moves existing reminder")
        let beforeAuth = service.authorizationCalls
        await manager.setReminder(for: unconfirmed, seasonIndex: 2)
        check(service.authorizationCalls == beforeAuth, "unconfirmed save never starts scheduling")
        unconfirmed.automaticReference = farm.automaticReference
        unconfirmed.compatibility = FarmCompatibility(metadataVersion: 348)
        check(!ReminderRules.canSchedule(unconfirmed), "unconfirmed metadata rejects planning")
        unconfirmed.compatibility = FarmCompatibility(rejectedVersions: [349])
        check(!ReminderRules.canSchedule(unconfirmed), "rejected version rejects planning")
        var missing = farm; missing.automaticReference = nil
        check(!ReminderRules.canSchedule(missing), "no reference rejects planning")
        manager.updateFarms([farm]); await manager.reconcile()
        let restored = ReminderManager(service: service, defaults: defaults, clock: { now })
        restored.updateFarms([farm]); await restored.reconcile(); await restored.restoreSystemRequests()
        check(restored.reminders == manager.reminders, "persistence restores full identity and request")
        now = initial.scheduledAt.addingTimeInterval(10)
        manager.updateFarms([farm]); await manager.reconcile()
        check(manager.active(for: identity, at: now) == nil && manager.reminders[0].state == .expired,
              "past one-shot expires without rolling to following cycle")
        check(service.scheduled.count == 3, "expiration creates no second request")
        await manager.setReminder(for: farm, seasonIndex: 2)
        check(manager.active(for: identity, at: now) != nil, "explicit new user request may schedule again")
        farm.registered = false
        manager.updateFarms([farm]); await manager.reconcile()
        check(manager.reminders[0].state == .cancelled && service.pending.isEmpty, "authoritative inactive state cancels pending request")
        let reused = FarmIdentity(sourceID: source, slotIndex: 16, creationTime: 5678)
        var other = farm; other.identity = reused; other.registered = true
        manager.updateFarms([farm, other]); await manager.reconcile()
        check(manager.active(for: reused, at: now) == nil, "slot reuse never inherits reminder")
        manager.updateFarms([other]); await manager.reconcile()
        check(manager.reminders.isEmpty, "permanent tracker removal deletes reminder data")
        service.allowed = false
        await manager.setReminder(for: other, seasonIndex: 1)
        check(manager.reminders.isEmpty && manager.errorMessage != nil, "denied permission never records success")
        service.allowed = true; service.fail = true
        await manager.setReminder(for: other, seasonIndex: 1)
        check(manager.reminders.isEmpty && manager.errorMessage != nil, "schedule failure never records success")
        service.fail = false
        await manager.setReminder(for: other, seasonIndex: 1)
        let active = manager.reminders[0]
        other.name = "Another name"; service.fail = true
        manager.updateFarms([other]); await manager.reconcile()
        check(manager.reminders[0] == active && service.pending.contains(active.requestID), "update failure retains prior registered request")
        service.fail = false
        manager.cancel(identity: reused)
        check(manager.reminders.isEmpty && service.pending.isEmpty, "explicit cancel removes persistence and system request")

        let payload: [AnyHashable: Any] = ["sourceID": source.uuidString, "slotIndex": 16, "creationTime": "5678"]
        check(MacNotificationService.identity(from: payload) == reused, "routing payload carries complete identity")
        check(MacNotificationService.identity(from: ["slotIndex":16]) == nil, "incomplete payload cannot route")
        var navigation = FarmNavigation()
        navigation.open(reused)
        other.hidden = true
        check(navigation.detail(in: [], knownFarms: [other])?.identity == reused, "hidden notification target opens without showing hidden overview")
        check(navigation.detail(in: [], knownFarms: []) == nil, "missing notification target cannot open wrong farm")
        let anotherSource = FarmIdentity(sourceID: UUID(), slotIndex: reused.slotIndex, creationTime: reused.creationTime)
        var foreign = other; foreign.identity = anotherSource
        navigation.open(anotherSource)
        check(navigation.detail(in: [other], knownFarms: [other, foreign])?.identity == anotherSource,
              "notification routing can open exact stored identity from another source without changing current source")

        let router = ReminderRouter()
        var opened = 0
        router.openWindow = { opened += 1 }
        let token = router.requestToken
        router.request(reused)
        check(router.identity == reused && router.requestToken != token && opened == 1, "warm notification routing invokes window opener")
        router.consume()
        check(router.identity == nil, "handled route cannot reopen later navigation")
        let coldRouter = ReminderRouter()
        coldRouter.request(identity)
        check(coldRouter.identity == identity, "cold route waits for view initialization")
        coldRouter.consume()
        check(!other.hidden || FarmPresentationSession().showHiddenFarms == false, "routing does not change hidden session state")

        service.fail = false
        await manager.setReminder(for: other, seasonIndex: 1)
        let missingRequest = manager.reminders[0]
        service.pending.remove(missingRequest.requestID)
        let missingRestore = ReminderManager(service: service, defaults: defaults, clock: { now })
        missingRestore.updateFarms([other]); await missingRestore.reconcile(); await missingRestore.restoreSystemRequests()
        check(missingRestore.reminders[0].state == .cancelled, "missing system request is not shown as active or silently recreated")
        check(service.scheduled.last?.id == missingRequest.id, "restore cannot silently reschedule missing request")

        let bindingSuite = suite + ".binding"
        let bindingDefaults = UserDefaults(suiteName: bindingSuite)!
        defer { bindingDefaults.removePersistentDomain(forName: bindingSuite) }
        let farmManager = FarmManager(defaults: bindingDefaults)
        farmManager.catalog.farms = [other]
        let bindingService = FakeNotifications()
        let bound = ReminderManager(service: bindingService, defaults: bindingDefaults, clock: { now })
        bound.bind(to: farmManager)
        while bound.restoring { await Task.yield() }
        await Task.yield()
        await bound.reconcile()
        await bound.setReminder(for: other, seasonIndex: 2)
        check(bound.active(for: reused, at: now) != nil, "manager binding initializes all stored farms")
        farmManager.catalog.farms[0].registered = false
        await Task.yield()
        await bound.reconcile()
        check(bound.reminders[0].state == .cancelled && bindingService.pending.isEmpty,
              "real catalog publish propagates authoritative inactivity")
        farmManager.catalog.farms[0].registered = true
        await Task.yield()
        await bound.reconcile()
        check(bound.active(for: reused, at: now) == nil, "reactivation does not silently re-arm cancelled reminder")
        farmManager.catalog.farms = []
        await Task.yield()
        await bound.reconcile()
        check(bound.reminders.isEmpty, "real catalog deletion removes reminder persistence")

        let oldInactive = SeasonReminder(id: UUID(), farmIdentity: identity, seasonIndex: 3, createdAt: now,
            scheduledAt: now.addingTimeInterval(30), reference: reference(0), farmName: "Old", state: .pending)
        check(oldInactive.farmIdentity != reused, "same slot with changed creation time is separate reminder identity")
        print("Passed \(checks) reminder checks")
    }
}
