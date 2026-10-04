import SwiftUI

struct FarmReminderView: View {
    @EnvironmentObject private var reminders: ReminderManager
    let farm: FarmData
    @State private var selectedSeason = 0

    static func seasonName(_ index: Int) -> String {
        switch index {
        case 0: return String(localized: "Frühling")
        case 1: return String(localized: "Sommer")
        case 2: return String(localized: "Herbst")
        default: return String(localized: "Winter")
        }
    }

    var body: some View {
        GroupBox(String(localized: "Saison-Erinnerung")) {
            VStack(alignment: .leading, spacing: 10) {
                if let reminder = reminders.active(for: farm.identity) {
                    Text(String(localized: "Erinnerung: \(Self.seasonName(reminder.seasonIndex))"))
                    Text(reminder.scheduledAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Geplanter Zeitpunkt"))
                    Button(String(localized: "Erinnerung abbrechen")) {
                        if let identity = farm.identity { reminders.cancel(identity: identity) }
                    }
                    .disabled(reminders.busy || reminders.restoring)
                } else {
                    Picker(String(localized: "Saison"), selection: $selectedSeason) {
                        ForEach(0..<4, id: \.self) { index in Text(Self.seasonName(index)).tag(index) }
                    }
                    Button(String(localized: "Erinnerung setzen")) {
                        Task { await reminders.setReminder(for: farm, seasonIndex: selectedSeason) }
                    }
                    .disabled(reminders.busy || reminders.restoring || !ReminderRules.canSchedule(farm))
                    if !ReminderRules.canSchedule(farm) {
                        Text(String(localized: "Für diese Farm liegt kein bestätigter Spielstand für eine Erinnerung vor."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .alert(String(localized: "Saison-Erinnerung"), isPresented: Binding(
            get: { reminders.errorMessage != nil }, set: { if !$0 { reminders.errorMessage = nil } })) {
            Button(String(localized: "OK"), role: .cancel) { reminders.errorMessage = nil }
        } message: { Text(reminders.errorMessage ?? "") }
    }
}

// A weak public AppKit window handle prevents a closed window's retained SwiftUI
// view from consuming a notification intended for the newly opened window.
@MainActor
final class ReminderWindowHandle {
    weak var window: NSWindow?
}

struct ReminderWindowAnchor: NSViewRepresentable {
    let handle: ReminderWindowHandle
    func makeNSView(context: Context) -> NSView { AnchorView(handle: handle) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AnchorView: NSView {
        let handle: ReminderWindowHandle
        init(handle: ReminderWindowHandle) {
            self.handle = handle
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle.window = window
        }
    }
}
