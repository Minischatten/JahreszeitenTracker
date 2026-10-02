//
//  JahreszeitenTrackerApp.swift
//  JahreszeitenTracker
//
//  JahreszeitenTracker project.
//

import SwiftUI

@main
struct JahreszeitenTrackerApp: App {
    // Retain the manager without observing its catalog in the scene/command owner.
    @State private var manager = FarmManager()
    @StateObject private var session = FarmPresentationSession()

    var body: some Scene {
        WindowGroup("JahreszeitenTracker") {
            ContentView()
                .environmentObject(manager)
                .environmentObject(session)
        }
        .defaultSize(width: 640, height: 780)
        .commands {
            FarmPresentationCommands(session: session)
        }
        Settings {
            SettingsView()
                .environmentObject(manager)
                .environmentObject(session)
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
