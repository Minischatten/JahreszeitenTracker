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
        WindowGroup {
            ContentView()
                .environmentObject(manager)
        }
    }
}
