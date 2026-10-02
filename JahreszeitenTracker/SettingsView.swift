import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var manager: FarmManager

    var body: some View {
        Form {
            Section(loc("Farm Together 2 Spielstände", "Farm Together 2 saves")) {
                Text(loc("Wähle den Ordner aus, in dem Farm Together 2 deine Spielstände ablegt. Der JahreszeitenTracker erkennt deine Hauptfarmen darin automatisch.",
                         "Choose the folder where Farm Together 2 stores your saves. JahreszeitenTracker detects your main farms automatically."))
                if let path = manager.sourcePath {
                    Text(path)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(loc("Spielstandordner auswählen …", "Choose save folder …")) { manager.chooseSaveFolder() }
                    if manager.hasSaveFolder {
                        Button(loc("Zugriff entfernen", "Remove access")) { manager.disconnectSaveFolder() }
                    }
                }
                Text(loc("Normalerweise unter macOS: ~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/",
                         "Usually on macOS: ~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam ID>/"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc("Spielstände werden ausschließlich gelesen und niemals verändert.", "Saves are read only and never modified."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(loc("Spielstandzugriff", "Save access")) {
                if let notice = manager.catalogVersionNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(manager.settingsStatus)
                    .font(.callout)
                if manager.saveFolderAvailable {
                    Text(loc("Der JahreszeitenTracker liest neue Spielstände automatisch ein.", "JahreszeitenTracker reads new saves automatically."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(loc("Der Countdown funktioniert auch weiter, wenn der Spielstandordner vorübergehend nicht verfügbar ist. Dafür verwendet der JahreszeitenTracker den zuletzt gelesenen Spielstand.",
                         "The countdown continues when the save folder is temporarily unavailable, using the last save read by JahreszeitenTracker."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
        .navigationTitle(loc("Einstellungen", "Settings"))
    }
}
