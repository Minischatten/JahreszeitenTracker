import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var manager: FarmManager

    var body: some View {
        Form {
            Section(loc("FT2-Speicherort", "FT2 storage folder")) {
                if let path = manager.sourcePath {
                    Text(path)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(loc("Kein Speicherort verbunden", "No storage folder connected"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(loc("Speicherort auswählen…", "Choose storage folder…")) { manager.chooseSaveFolder() }
                    if manager.hasSaveFolder {
                        Button(loc("Trennen", "Disconnect")) { manager.disconnectSaveFolder() }
                    }
                }
                Text(loc("Wähle den Ordner mit farms.mlk und dem Unterordner farms. Spielstände werden ausschließlich gelesen.",
                         "Choose the folder containing farms.mlk and the farms subfolder. Saves are read only."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(loc("Verbindung", "Connection")) {
                Text(manager.settingsStatus)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc("Ohne Verbindung läuft der Countdown mit dem letzten gültigen Spielstand weiter.",
                         "Without a connection, the countdown continues from the last valid save."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
