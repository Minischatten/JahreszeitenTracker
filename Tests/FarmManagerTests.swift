import Foundation
import Combine

func loc(_ de: String, _ en: String) -> String { de }

@main
@MainActor
struct FarmManagerTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }
    static func main() throws {
        let suite = "FT2TrackerManagerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Data("obsolete four-farm configuration".utf8)
        defaults.set(old, forKey: "savedFarmsData_v1")
        let manager = FarmManager(defaults: defaults)
        check(manager.farms.isEmpty, "manager ignores old four-farm key")
        check(manager.farms.isEmpty, "empty catalog controls safe")
        manager.catalog.selectSource(path: "/synthetic-only", bookmark: Data([1]))
        let source = manager.catalog.activeSourceID!
        let ticks: Int64 = 639_263_913_480_000_000
        let a = SaveReference(gameTime: 100, savedTicks: ticks, nextBoundary: 500, seasonIndex: 0, sourceName: "farm_0_0.data")
        let b = SaveReference(gameTime: 200, savedTicks: ticks, nextBoundary: 300, seasonIndex: 3, sourceName: "farm_16_0.data")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: ticks - 10_000_000, name: "A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: ticks - 10_000_000, name: "B"), reference: b, message: "")
        ], sourceID: source)
        check(manager.farms.count == 2, "manager dynamic count")
        check(manager.state(for: manager.farms[0], at: a.savedAt) == SeasonState(seasonIndex: 0, remaining: 400), "first farm state")
        manager.selectedFarmIdentity = manager.farms[1].identity
        check(manager.state(for: manager.farms[1], at: b.savedAt) == SeasonState(seasonIndex: 3, remaining: 100), "second farm independent state")
        var publications = 0
        let subscription = manager.objectWillChange.sink { publications += 1 }
        let persistedBefore = defaults.data(forKey: "ft2FarmCatalog_v2")
        for _ in 0..<10 {
            manager.selectedFarmIdentity = manager.selectedFarmIdentity
            manager.selectedFarmIdentity = nil
        }
        check(publications == 0, "picker no-op and transient nil selections do not publish")
        check(defaults.data(forKey: "ft2FarmCatalog_v2") == persistedBefore, "picker no-op leaves persistence untouched")
        manager.selectedFarmIdentity = manager.farms[0].identity
        check(publications == 1, "real farm selection publishes once")
        manager.selectedFarmIdentity = manager.farms[1].identity
        subscription.cancel()
        let reloaded = FarmManager(defaults: defaults)
        check(reloaded.selectedFarmIdentity == manager.farms[1].identity, "identity selection persisted")
        check(reloaded.farms[1].automaticReference == b, "reference persisted")
        check(defaults.data(forKey: "savedFarmsData_v1") == old, "obsolete key neither read nor rewritten")
        var persisted = try JSONSerialization.jsonObject(with: defaults.data(forKey: "ft2FarmCatalog_v2")!) as! [String: Any]
        persisted["legacyFarms"] = [["name": "obsolete"]]
        persisted.removeValue(forKey: "selectedFarmIdentity")
        persisted["preferredViewMode"] = "overview"
        persisted["selectedFarmID"] = manager.farms[1].id
        var oldFarms = persisted["farms"] as! [[String: Any]]
        for i in oldFarms.indices {
            oldFarms[i]["manualCorrection"] = 25
            oldFarms[i]["automaticEnabled"] = false
            oldFarms[i]["isTimerRunning"] = false
            oldFarms[i]["startSeason"] = "summer"
            oldFarms[i]["initialRemainingMinutes"] = 8
            oldFarms[i]["absoluteStartTimeInterval"] = 1000
        }
        persisted["farms"] = oldFarms
        defaults.set(try JSONSerialization.data(withJSONObject: persisted), forKey: "ft2FarmCatalog_v2")
        let cleaned = FarmManager(defaults: defaults)
        check(cleaned.farms[1].automaticReference == b
              && cleaned.selectedFarmIdentity == manager.farms[1].identity
              && cleaned.catalog.sources == manager.catalog.sources, "existing identities bookmarks references and selection preserved")
        check(cleaned.state(for: cleaned.farms[1], at: b.savedAt) == b.state(at: b.savedAt), "old manual state cannot affect automatic countdown")
        let cleanJSON = try JSONSerialization.jsonObject(with: defaults.data(forKey: "ft2FarmCatalog_v2")!) as! [String: Any]
        check(cleanJSON["preferredViewMode"] == nil, "obsolete view mode removed without losing identities or references")
        check(cleanJSON["legacyFarms"] == nil, "manager persist removes archive")
        let encodedFarms = cleanJSON["farms"] as! [[String: Any]]
        check(encodedFarms.allSatisfy { farm in
            ["manualCorrection", "automaticEnabled", "isTimerRunning", "startSeason", "initialRemainingMinutes", "absoluteStartTimeInterval"].allSatisfy { farm[$0] == nil }
        }, "manual fields not persisted")
        check(cleanJSON["selectedFarmID"] == nil && cleanJSON["selectedFarmIdentity"] != nil, "selection stored by farm identity")
        reloaded.disconnectSaveFolder()
        check(!reloaded.hasSaveFolder && reloaded.farms[1].automaticReference == b, "disconnect retains reference")
        check(reloaded.visibleFarms.count == 2 && reloaded.state(for: reloaded.farms[1], at: b.savedAt) == b.state(at: b.savedAt), "disconnect still presents last references")
        check(FarmSyncState.forFarm(reloaded.farms[1]) == .lastStand, "disconnected reference status")
        print("Passed \(checks) manager checks")
    }
}
