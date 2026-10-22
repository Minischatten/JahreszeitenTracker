import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image("WSS_Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .accessibilityLabel(String(localized: "Wird schon Software Logo"))

            VStack(spacing: 6) {
                Text(verbatim: "JahreszeitenTracker")
                    .font(.title2.weight(.semibold))
                Text(String(localized: "Version \(version) (\(build))"))
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "Kostenloses Hobbyprojekt für Farm Together 2"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "E-Mail:"))
                        .foregroundStyle(.primary)
                        .gridColumnAlignment(.trailing)
                    Link(destination: URL(string: "mailto:kontakt@wirdschonsoftware.com")!) {
                        Text(verbatim: "kontakt@wirdschonsoftware.com")
                    }
                }
                GridRow {
                    Text(String(localized: "Webseite:"))
                        .foregroundStyle(.primary)
                    Link(destination: URL(string: "https://wirdschonsoftware.com")!) {
                        Text(verbatim: "wirdschonsoftware.com")
                    }
                }
            }

            Text(String(localized: "Dieses Projekt steht in keiner Verbindung zu Milkstone Studios und wird von Milkstone Studios weder entwickelt noch unterstützt."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(verbatim: "© 2026 WirdSchonSoftware")
                Text(String(localized: "Quellcode: GPL-3.0-only\nBranding separat lizenziert."))
            }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 380)
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "Über JahreszeitenTracker")) {
                openWindow(id: "about")
            }
        }
    }
}
