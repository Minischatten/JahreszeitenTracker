//
//  JahreszeitenTrackerApp.swift
//  JahreszeitenTracker
//
//  JahreszeitenTracker project.
//

import SwiftUI

@main
struct JahreszeitenTrackerApp: App {
    @StateObject private var manager = FarmManager()

    var body: some Scene {
        WindowGroup("JahreszeitenTracker") {
            ContentView()
                .environmentObject(manager)
        }
        .defaultSize(width: 640, height: 780)
        Settings {
            SettingsView()
                .environmentObject(manager)
        }
    }
}
