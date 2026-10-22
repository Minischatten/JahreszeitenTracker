import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var manager: FarmManager

    private let saveFolderHint = "~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/"

    var body: some View {
        Form {
            Section(String(localized: "Farm Together 2 Spielstände")) {
                Text(String(localized: "Wähle den Ordner aus, in dem Farm Together 2 deine Spielstände ablegt. Der JahreszeitenTracker erkennt deine Hauptfarmen darin automatisch."))
                if let path = manager.sourcePath {
                    Text(path)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(String(localized: "Spielstandordner auswählen …")) { manager.chooseSaveFolder() }
                    if manager.hasSaveFolder {
                        Button(String(localized: "Zugriff entfernen")) { manager.disconnectSaveFolder() }
                    }
                }
                Text(String(localized: "Normalerweise unter: \(saveFolderHint)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "Spielstände werden ausschließlich gelesen und niemals verändert."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "Spielstandzugriff")) {
                if let notice = manager.catalogVersionNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(manager.settingsStatus)
                    .font(.callout)
                if manager.saveFolderAvailable {
                    Text(String(localized: "Der JahreszeitenTracker liest neue Spielstände automatisch ein."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "Der Countdown funktioniert auch weiter, wenn der Spielstandordner vorübergehend nicht verfügbar ist. Dafür verwendet der JahreszeitenTracker den zuletzt gelesenen Spielstand."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
        .navigationTitle(String(localized: "Einstellungen"))
    }
}
