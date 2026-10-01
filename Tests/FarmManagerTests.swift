import Foundation

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
        manager.adjustTime(by: 1); manager.startManually(); manager.syncToCurrentSeasonStart()
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
        check(manager.state(at: a.savedAt) == SeasonState(seasonIndex: 0, remaining: 400), "first farm state")
        manager.selectedFarmIndex = 1
        check(manager.state(at: b.savedAt) == SeasonState(seasonIndex: 3, remaining: 100), "second farm independent state")
        manager.adjustTime(by: 2)
        check(manager.farms[1].manualCorrection == 2 && manager.farms[0].manualCorrection == 0, "manual adjustment isolated")
        check(manager.state(at: b.savedAt) == SeasonState(seasonIndex: 3, remaining: 102), "manual semantics unchanged")
        let reloaded = FarmManager(defaults: defaults)
        check(reloaded.selectedFarmIndex == 1 && reloaded.farms[1].manualCorrection == 2, "manager persistence and selection")
        check(defaults.data(forKey: "savedFarmsData_v1") == old, "obsolete key neither read nor rewritten")
        var persisted = try JSONSerialization.jsonObject(with: defaults.data(forKey: "ft2FarmCatalog_v2")!) as! [String: Any]
        persisted["legacyFarms"] = [["name": "obsolete"]]
        defaults.set(try JSONSerialization.data(withJSONObject: persisted), forKey: "ft2FarmCatalog_v2")
        let cleaned = FarmManager(defaults: defaults)
        check(cleaned.farms[1].automaticReference == b && cleaned.farms[1].manualCorrection == 2
              && cleaned.selectedFarmIndex == 1 && cleaned.catalog.sources == manager.catalog.sources, "manager preserves active catalog when dropping archive")
        let cleanJSON = try JSONSerialization.jsonObject(with: defaults.data(forKey: "ft2FarmCatalog_v2")!) as! [String: Any]
        check(cleanJSON["legacyFarms"] == nil, "manager persist removes archive")
        reloaded.disconnectSaveFolder()
        check(!reloaded.hasSaveFolder && reloaded.farms[1].automaticReference == b, "disconnect retains reference")
        print("Passed \(checks) manager checks")
    }
}
