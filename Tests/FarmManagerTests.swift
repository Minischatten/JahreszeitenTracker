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
        let firstIdentity = manager.farms[0].identity!
        let oldIdentity = manager.farms[1].identity!
        let oldID = manager.farms[1].id
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: ticks + 10_000_000, name: "New B"), reference: nil, message: "No save")
        ], sourceID: source)
        let newIdentity = manager.farms[2].identity!
        check(manager.visibleFarms.map(\.identity) == [firstIdentity, oldIdentity, newIdentity], "reused slot keeps inactive farm in place and appends new identity")
        check(manager.farms[1].automaticReference == b && FarmSyncState.forFarm(manager.farms[1]) == .notFound,
              "old reused-slot record retains countdown and neutral status")
        check(!manager.farms[2].isInactive && manager.farms[2].automaticReference == nil,
              "new reused-slot farm does not inherit old reference")
        manager.selectedFarmIdentity = oldIdentity
        let sourcesBeforeDelete = manager.catalog.sources
        let beforeDelete = defaults.data(forKey: "ft2FarmCatalog_v2")
        check(!manager.removeInactiveFarm(identity: newIdentity), "active farm cannot be removed")
        check(defaults.data(forKey: "ft2FarmCatalog_v2") == beforeDelete, "refused delete leaves persistence unchanged")
        check(manager.removeInactiveFarm(identity: oldIdentity), "confirmed inactive tracker deletion succeeds")
        check(!manager.farms.contains { $0.identity == oldIdentity || $0.id == oldID }
              && manager.catalog.selectedFarmIdentity == nil, "all farm data and selected identity removed")
        check(manager.catalog.sources == sourcesBeforeDelete && manager.farms[0].automaticReference == a
              && manager.farms[1].identity == newIdentity, "other farms sources bookmarks and reused slot preserved")
        let afterDelete = FarmManager(defaults: defaults)
        check(afterDelete.farms.count == 2 && !afterDelete.farms.contains { $0.identity == oldIdentity },
              "deleted farm does not return after reload")
        check(!manager.removeInactiveFarm(identity: oldIdentity), "repeated deletion is a no-op")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "New B"), reference: nil, message: "No save")
        ], sourceID: source)
        check(manager.farms.count == 2 && !manager.farms.contains { $0.identity == oldIdentity },
              "later scans do not resurrect removed unregistered identity")
        // Reordering uses the existing array, including inactive records.
        check(manager.moveFarm(newIdentity, to: firstIdentity), "drop moves last card to first")
        check(manager.visibleFarms.map(\.identity) == [newIdentity, firstIdentity], "custom order applied")
        let reorderedReload = FarmManager(defaults: defaults)
        check(reorderedReload.visibleFarms.map(\.identity) == [newIdentity, firstIdentity], "custom order survives restart")
        let moveSaved = defaults.data(forKey: "ft2FarmCatalog_v2")
        check(!manager.moveFarm(newIdentity, to: newIdentity)
              && !manager.moveFarm(oldIdentity, to: firstIdentity), "self and stale drops refused")
        check(defaults.data(forKey: "ft2FarmCatalog_v2") == moveSaved, "invalid drops do not rewrite persistence")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save")
        ], sourceID: source)
        check(manager.visibleFarms.map(\.identity) == [newIdentity, firstIdentity]
              && manager.farms[1].name == "Renamed A", "rename and metadata order do not reorder cards")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save")
        ], sourceID: source)
        check(manager.visibleFarms.map(\.identity) == [newIdentity, firstIdentity]
              && manager.farms[1].isInactive, "unregistered farm retains custom position")
        check(manager.moveFarm(firstIdentity, to: newIdentity)
              && manager.visibleFarms.map(\.identity) == [firstIdentity, newIdentity], "inactive card can move")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save"),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 48, creationTime: ticks, name: "New C"), reference: a, message: "")
        ], sourceID: source)
        let thirdIdentity = manager.farms[2].identity!
        check(manager.visibleFarms.map(\.identity) == [firstIdentity, newIdentity, thirdIdentity]
              && !manager.farms[0].isInactive, "reactivation keeps position and new farm appends")
        check(manager.moveFarm(firstIdentity, to: thirdIdentity)
              && manager.visibleFarms.map(\.identity) == [newIdentity, thirdIdentity, firstIdentity], "forward drop moves first card to last")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 48, creationTime: thirdIdentity.creationTime, name: "New C"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: ticks + 20_000_000, name: "Reused B"), reference: nil, message: "No save")
        ], sourceID: source)
        let reusedIdentity = manager.farms[3].identity!
        check(manager.visibleFarms.map(\.identity) == [newIdentity, thirdIdentity, firstIdentity, reusedIdentity]
              && manager.farms[0].isInactive, "slot reuse appends distinct identity without moving or reactivating old record")
        check(manager.removeInactiveFarm(identity: newIdentity)
              && manager.visibleFarms.map(\.identity) == [thirdIdentity, firstIdentity, reusedIdentity], "delete removes only its position")
        check(manager.catalog.sources == sourcesBeforeDelete && manager.catalog.activeSourceID == source
              && manager.farms[1].automaticReference == a, "ordering preserves bookmarks sources and references")
        let finalReload = FarmManager(defaults: defaults)
        check(finalReload.visibleFarms.map(\.identity) == [thirdIdentity, firstIdentity, reusedIdentity], "final order and deletion persist together")
        var multiSource = manager.catalog
        let foreignSource = UUID()
        let foreign = FarmData(id: 100, name: "Foreign", identity: FarmIdentity(sourceID: foreignSource, slotIndex: 0, creationTime: ticks))
        multiSource.farms.insert(foreign, at: 1)
        let recordsBefore = multiSource.farms
        check(multiSource.moveFarm(reusedIdentity, to: thirdIdentity)
              && multiSource.farms[1] == foreign, "other source retains exact array position")
        check(Set(multiSource.farms.compactMap(\.identity)) == Set(recordsBefore.compactMap(\.identity))
              && multiSource.farms.allSatisfy { recordsBefore.contains($0) }, "move changes only order not farm data")
        check(!multiSource.moveFarm(thirdIdentity, to: foreign.identity!), "cross-source drop refused")
        let beforeVersion = manager.catalog
        let knownFarm = manager.farms.first { $0.registered == true && $0.automaticReference != nil }!
        let knownIdentity = knownFarm.identity!
        let previousReference = knownFarm.automaticReference!
        let futureReference = SaveReference(gameTime: previousReference.gameTime, savedTicks: previousReference.savedTicks + 10_000_000,
            nextBoundary: previousReference.nextBoundary, seasonIndex: previousReference.seasonIndex,
            sourceName: previousReference.sourceName, saveVersion: 348)
        let unconfirmedScan = CatalogScanResult(readings: [
            FarmReading(metadata: FT2FarmMetadata(slotIndex: knownIdentity.slotIndex, creationTime: knownIdentity.creationTime, name: "Unsafe rename"), reference: futureReference, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 99, creationTime: ticks, name: "Unsafe new farm"), reference: futureReference, message: "")
        ], message: "", refreshedBookmark: nil, metadataVersion: 348)
        manager.catalog.apply(unconfirmedScan, sourceID: source)
        check(manager.farms.map(\.identity) == beforeVersion.farms.map(\.identity), "unconfirmed scan keeps persistent identities and order")
        check(manager.farms.first { $0.identity == knownIdentity }?.name == knownFarm.name, "unconfirmed scan preserves names")
        check(manager.catalogVersionNotice?.contains("348") == true, "central notice includes real version and deferred changes")
        let versionReload = FarmManager(defaults: defaults)
        let versionFarm = versionReload.farms.first { $0.identity == knownIdentity }!
        check(versionFarm.automaticReference?.version == 348 && FarmSyncState.forFarm(versionFarm) == .unconfirmedVersion, "manager persistence retains reference provenance and warning after restart")
        check(versionReload.catalogVersionNotice == manager.catalogVersionNotice, "catalog notice survives restart")
        manager.catalog.apply(CatalogScanResult(readings: nil, message: "invalid future metadata", refreshedBookmark: nil,
            metadataVersion: 349, metadataRejected: true), sourceID: source)
        check(manager.farms.first { $0.identity == knownIdentity }?.registered == true, "failed future scan never marks registered farm removed")
        check(manager.farms.first { $0.identity == knownIdentity }?.automaticReference == futureReference, "failed future scan never overwrites valid reference")
        let failureReload = FarmManager(defaults: defaults)
        let failureFarm = failureReload.farms.first { $0.identity == knownIdentity }!
        check(FarmSyncState.forFarm(failureFarm) == .lastStandNewVersion && failureReload.catalogVersionNotice?.contains("349") == true, "failure warning and source metadata persist")
        manager.catalog.apply(CatalogScanResult(readings: nil, message: "temporarily inaccessible", refreshedBookmark: nil), sourceID: source)
        check(manager.farms.first { $0.identity == knownIdentity }?.compatibility?.metadataRejected == true, "access failure cannot erase previous compatibility warning")
        manager.catalog.merge(beforeVersion.farms.filter { $0.registered == true }.map { farm in
            FarmReading(metadata: FT2FarmMetadata(slotIndex: farm.identity!.slotIndex, creationTime: farm.identity!.creationTime, name: farm.name), reference: farm.automaticReference, message: "")
        }, sourceID: source)
        check(FarmSyncState.forFarm(manager.farms.first { $0.identity == knownIdentity }!) == .unconfirmedVersion,
              "older compatible fallback cannot roll future reference back or turn green")
        print("Passed \(checks) manager checks")
    }
}
