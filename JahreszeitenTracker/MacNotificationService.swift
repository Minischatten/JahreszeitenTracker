import AppKit
import UserNotifications
import Combine

@MainActor
final class ReminderRouter: ObservableObject {
    static let shared = ReminderRouter()
    @Published private(set) var identity: FarmIdentity?
    @Published private(set) var requestToken = UUID()
    func consume() { identity = nil }
    var openWindow: (() -> Void)?

    func request(_ identity: FarmIdentity) {
        self.identity = identity
        requestToken = UUID()
        openWindow?()
        NSApp?.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class MacNotificationService: NSObject, ReminderNotifications, UNUserNotificationCenterDelegate {
    static let shared = MacNotificationService()
    private let center = UNUserNotificationCenter.current()

    func installDelegate() { center.delegate = self }

    func authorize() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return try await center.requestAuthorization(options: [.alert, .sound])
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    static func content(for reminder: SeasonReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let name = reminder.farmName
        switch reminder.seasonIndex {
        case 0:
            content.title = String(localized: "Frühling hat begonnen")
            content.body = String(localized: "Auf „\(name)“ ist jetzt Frühling.")
        case 1:
            content.title = String(localized: "Sommer hat begonnen")
            content.body = String(localized: "Auf „\(name)“ ist jetzt Sommer.")
        case 2:
            content.title = String(localized: "Herbst hat begonnen")
            content.body = String(localized: "Auf „\(name)“ ist jetzt Herbst.")
        default:
            content.title = String(localized: "Winter hat begonnen")
            content.body = String(localized: "Auf „\(name)“ ist jetzt Winter.")
        }
        content.sound = .default
        let identity = reminder.farmIdentity
        content.userInfo = ["sourceID": identity.sourceID.uuidString, "slotIndex": identity.slotIndex,
                            "creationTime": String(identity.creationTime)]
        return content
    }

    func schedule(_ reminder: SeasonReminder) async throws {
        let content = Self.content(for: reminder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Calendar triggers resolve to whole seconds. Never notify before the calculated boundary.
        let date = Date(timeIntervalSince1970: ceil(reminder.scheduledAt.timeIntervalSince1970))
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.requestID, content: content, trigger: trigger))
    }

    func remove(_ requestIDs: [String]) { center.removePendingNotificationRequests(withIdentifiers: requestIDs) }
    func pendingIDs() async -> Set<String> { Set(await center.pendingNotificationRequests().map(\.identifier)) }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.identifier.hasPrefix("season-reminder."),
              response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let identity = Self.identity(from: response.notification.request.content.userInfo) else {
            completionHandler(); return
        }
        Task { @MainActor in
            ReminderRouter.shared.request(identity)
            completionHandler()
        }
    }

    nonisolated static func identity(from payload: [AnyHashable: Any]) -> FarmIdentity? {
        guard let source = payload["sourceID"] as? String, let sourceID = UUID(uuidString: source),
              let slot = payload["slotIndex"] as? Int, slot >= 0,
              let creation = payload["creationTime"] as? String, let creationTime = Int64(creation) else { return nil }
        return FarmIdentity(sourceID: sourceID, slotIndex: slot, creationTime: creationTime)
    }
}

@MainActor
final class ReminderApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MacNotificationService.shared.installDelegate()
    }
}
