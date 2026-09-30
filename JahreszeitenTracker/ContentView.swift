//
//  ContentView.swift
//  JahreszeitenTracker
//
//  JahreszeitenTracker project.
//
import SwiftUI
import Combine

// MARK: - Sprach-System (DE / EN)
var isGermanSystem: Bool {
    let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
    return lang.hasPrefix("de")
}

func loc(_ de: String, _ en: String) -> String {
    return isGermanSystem ? de : en
}

// MARK: - Jahreszeiten Model
enum Season: String, CaseIterable, Identifiable, Codable {
    case spring, summer, autumn, winter
    
    var id: String { self.rawValue }
    
    func name(isGerman: Bool = isGermanSystem) -> String {
        switch self {
        case .spring: return isGerman ? "Frühling" : "Spring"
        case .summer: return isGerman ? "Sommer" : "Summer"
        case .autumn: return isGerman ? "Herbst" : "Autumn"
        case .winter: return isGerman ? "Winter" : "Winter"
        }
    }
    
    var next: Season {
        switch self {
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        case .winter: return .spring
        }
    }
}

// MARK: - UI Hauptansicht
struct ContentView: View {
    @EnvironmentObject private var manager: FarmManager
    
    @State private var currentSeason: Season = .spring
    @State private var timeRemainingInCurrentSeason: TimeInterval = 0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var currentFarm: FarmData {
        manager.farms[manager.selectedFarmIndex]
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Titel
            Text(loc("Jahreszeiten Tracker", "Season Tracker"))
                .font(.title2)
                .bold()
            
            // TAB-LEISTE FÜR DIE 4 FARMEN
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Button(action: {
                        manager.selectedFarmIndex = index
                        updateCurrentSeasonLogik()
                    }) {
                        HStack(spacing: 4) {
                            if manager.farms[index].isTimerRunning {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                            Text(manager.farms[index].name.isEmpty ? "Farm \(index + 1)" : manager.farms[index].name)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(manager.selectedFarmIndex == index ? .blue : .gray)
                }
            }
            
            // FARM-NAME EDITIEREN
            HStack {
                Text(loc("Farm Name:", "Farm Name:"))
                    .font(.caption)
                    .foregroundColor(.gray)
                TextField(loc("Name eingeben", "Enter name"), text: $manager.farms[manager.selectedFarmIndex].name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            
            HStack(spacing: 6) {
                Button(loc("FT2-Ordner…", "FT2 folder…")) { manager.chooseSaveFolder() }
                Menu("FT2 \(loc("Spielstand", "Save")): \(manager.sourceSlot + 1)") {
                    ForEach(0..<4, id: \.self) { slot in
                        Button("FT2 \(loc("Spielstand", "Save")) \(slot + 1)") { manager.setSourceSlot(slot) }
                    }
                }
                if manager.hasSaveFolder {
                    Button(loc("Trennen", "Disconnect")) { manager.disconnectSaveFolder() }
                }
            }
            .controlSize(.small)
            Text(manager.syncStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(manager.syncStatus)

            Divider()
            
            // HAUPTANZEIGE / EINSTELLUNGEN
            if currentFarm.isTimerRunning {
                // RUNNING VIEW
                VStack(spacing: 10) {
                    Text(loc("Aktuelle Jahreszeit:", "Current Season:"))
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text(currentSeason.name())
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(colorForSeason(currentSeason))
                    
                    Text("\(loc("Nächster Wechsel in:", "Next change in:")) \(formatTime(timeRemainingInCurrentSeason))")
                        .font(.title3)
                        .monospacedDigit()
                    
                    // FEINJUSTIERUNG (SEKUNDEN-BUTTONS)
                    VStack(spacing: 6) {
                        Text(loc("Feinjustierung:", "Fine Tuning:"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Button("-5s") { adjustTime(by: -5) }
                            Button("-1s") { adjustTime(by: -1) }
                            Button("+1s") { adjustTime(by: 1) }
                            Button("+5s") { adjustTime(by: 5) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(loc("Jetzt gestartet", "Started just now")) {
                            syncToCurrentSeasonStart()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(loc("Setzt die verbleibende Zeit der aktuellen Jahreszeit wieder exakt auf 17:00", "Resets remaining time of current season back to 17:00"))
                    }
                    .padding(.top, 2)
                    
                    Button(loc("Zurücksetzen / Einstellungen", "Reset / Settings")) {
                        manager.farms[manager.selectedFarmIndex].isTimerRunning = false
                    }
                    .padding(.top, 4)
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                
            } else {
                // CONFIGURATION VIEW
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(loc("Start-Jahreszeit:", "Starting Season:"))
                        Picker("", selection: $manager.farms[manager.selectedFarmIndex].startSeason) {
                            ForEach(Season.allCases) { season in
                                Text(season.name()).tag(season)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("\(loc("Verbleibende Zeit für Start-Jahreszeit:", "Remaining time for starting season:")) \(Int(currentFarm.initialRemainingMinutes)) Min.")
                            .font(.subheadline)
                        Slider(value: $manager.farms[manager.selectedFarmIndex].initialRemainingMinutes, in: 1...17, step: 1)
                    }
                    
                    Button(action: startTimer) {
                        Text(loc("Starten", "Start"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                }
                .padding(12)
            }
        }
        .padding()
        .frame(width: 480, height: 425)
        .onAppear(perform: updateCurrentSeasonLogik)
        .onChange(of: manager.farms) { _, _ in updateCurrentSeasonLogik() }
        .onChange(of: manager.selectedFarmIndex) { _, _ in updateCurrentSeasonLogik() }
        .onReceive(timer) { _ in
            updateCurrentSeasonLogik()
        }
    }
    
    // MARK: - Logik & Methoden
    func updateCurrentSeasonLogik() {
        let farm = currentFarm
        guard farm.isTimerRunning else { return }
        
        let state = manager.state(at: Date())
        self.currentSeason = Season.allCases[state.seasonIndex]
        self.timeRemainingInCurrentSeason = state.remaining
    }

    func adjustTime(by seconds: TimeInterval) {
        manager.adjustTime(by: seconds)
        updateCurrentSeasonLogik()
    }

    func syncToCurrentSeasonStart() {
        manager.syncToCurrentSeasonStart()
        updateCurrentSeasonLogik()
    }

    func startTimer() {
        manager.startManually()
        updateCurrentSeasonLogik()
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func colorForSeason(_ season: Season) -> Color {
        switch season {
        case .spring: return .green
        case .summer: return .orange
        case .autumn: return .brown
        case .winter: return .blue
        }
    }
}
