//
//  JahreszeitenTrackerApp.swift
//  JahreszeitenTracker
//
//  JahreszeitenTracker project.
//

import SwiftUI

@main
struct JahreszeitenTrackerApp: App {
    @NSApplicationDelegateAdaptor(ReminderApplicationDelegate.self) private var appDelegate
    @State private var reminders: ReminderManager
    @State private var router = ReminderRouter.shared
    // Retain the manager without observing its catalog in the scene/command owner.
    @State private var manager: FarmManager
    @StateObject private var session = FarmPresentationSession()

    init() {
        let manager = FarmManager()
        let reminders = ReminderManager(service: MacNotificationService.shared)
        reminders.bind(to: manager)
        _manager = State(initialValue: manager)
        _reminders = State(initialValue: reminders)
    }

    var body: some Scene {
        WindowGroup("JahreszeitenTracker", id: "main") {
            ContentView()
                .environmentObject(manager)
                .environmentObject(session)
                .environmentObject(reminders)
                .environmentObject(router)
        }
        .defaultSize(width: 640, height: 780)
        .commands {
            FarmPresentationCommands(session: session)
            AboutCommands()
        }
        Window(String(localized: "Über JahreszeitenTracker"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView()
                .environmentObject(manager)
                .environmentObject(session)
                .environmentObject(reminders)
                .environmentObject(router)
        }
    }

}

private struct FarmPresentationCommands: Commands {
    @ObservedObject var session: FarmPresentationSession

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle(String(localized: "Ausgeblendete Farmen einblenden"), isOn: $session.showHiddenFarms)
        }
    }

}
