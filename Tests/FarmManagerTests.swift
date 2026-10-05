import Foundation
import Combine

@main
@MainActor
struct FarmManagerTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }
    static func main() throws {
        let panelHome = FileManager.default.temporaryDirectory.appendingPathComponent("FT2PanelStart." + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: panelHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: panelHome) }
        let storage = panelHome.appendingPathComponent("Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage", isDirectory: true)
        check(FarmManager.saveFolderPanelStartURL(home: panelHome) == panelHome,
              "missing SteamStorage falls back to home")
        try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: storage)
        check(FarmManager.saveFolderPanelStartURL(home: panelHome) == panelHome,
              "SteamStorage file is not a usable initial directory")
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        check(FarmManager.saveFolderPanelStartURL(home: panelHome) == storage,
              "existing SteamStorage is the initial panel directory")
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("123456789"), withIntermediateDirectories: true)
        check(FarmManager.saveFolderPanelStartURL(home: panelHome) == storage,
              "Steam ID child is never selected automatically")
        let suite = "FT2TrackerManagerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Data("obsolete four-farm configuration".utf8)
        defaults.set(old, forKey: "savedFarmsData_v1")
        let session = FarmPresentationSession()
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
        check(reloaded.visibleFarms().count == 2 && reloaded.state(for: reloaded.farms[1], at: b.savedAt) == b.state(at: b.savedAt), "disconnect still presents last references")
        check(FarmSyncState.forFarm(reloaded.farms[1]) == .lastStand, "disconnected reference status")
        let firstIdentity = manager.farms[0].identity!
        let oldIdentity = manager.farms[1].identity!
        let oldID = manager.farms[1].id
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: ticks + 10_000_000, name: "New B"), reference: nil, message: "No save")
        ], sourceID: source)
        let newIdentity = manager.farms[2].identity!
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [firstIdentity, oldIdentity, newIdentity], "reused slot keeps inactive farm in place and appends new identity")
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
        check(manager.moveFarm(newIdentity, to: firstIdentity, showHiddenFarms: session.showHiddenFarms), "drop moves last card to first")
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [newIdentity, firstIdentity], "custom order applied")
        let reorderedReload = FarmManager(defaults: defaults)
        check(reorderedReload.visibleFarms().map(\.identity) == [newIdentity, firstIdentity], "custom order survives restart")
        let moveSaved = defaults.data(forKey: "ft2FarmCatalog_v2")
        check(!manager.moveFarm(newIdentity, to: newIdentity, showHiddenFarms: session.showHiddenFarms)
              && !manager.moveFarm(oldIdentity, to: firstIdentity, showHiddenFarms: session.showHiddenFarms), "self and stale drops refused")
        check(defaults.data(forKey: "ft2FarmCatalog_v2") == moveSaved, "invalid drops do not rewrite persistence")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save")
        ], sourceID: source)
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [newIdentity, firstIdentity]
              && manager.farms[1].name == "Renamed A", "rename and metadata order do not reorder cards")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save")
        ], sourceID: source)
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [newIdentity, firstIdentity]
              && manager.farms[1].isInactive, "unregistered farm retains custom position")
        check(manager.moveFarm(firstIdentity, to: newIdentity, showHiddenFarms: session.showHiddenFarms)
              && manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [firstIdentity, newIdentity], "inactive card can move")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: newIdentity.creationTime, name: "Renamed B"), reference: nil, message: "No save"),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 48, creationTime: ticks, name: "New C"), reference: a, message: "")
        ], sourceID: source)
        let thirdIdentity = manager.farms[2].identity!
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [firstIdentity, newIdentity, thirdIdentity]
              && !manager.farms[0].isInactive, "reactivation keeps position and new farm appends")
        check(manager.moveFarm(firstIdentity, to: thirdIdentity, showHiddenFarms: session.showHiddenFarms)
              && manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [newIdentity, thirdIdentity, firstIdentity], "forward drop moves first card to last")
        manager.catalog.merge([
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 0, creationTime: firstIdentity.creationTime, name: "Renamed A"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 48, creationTime: thirdIdentity.creationTime, name: "New C"), reference: a, message: ""),
            FarmReading(metadata: FT2FarmMetadata(slotIndex: 16, creationTime: ticks + 20_000_000, name: "Reused B"), reference: nil, message: "No save")
        ], sourceID: source)
        let reusedIdentity = manager.farms[3].identity!
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [newIdentity, thirdIdentity, firstIdentity, reusedIdentity]
              && manager.farms[0].isInactive, "slot reuse appends distinct identity without moving or reactivating old record")
        check(manager.removeInactiveFarm(identity: newIdentity)
              && manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [thirdIdentity, firstIdentity, reusedIdentity], "delete removes only its position")
        check(manager.catalog.sources == sourcesBeforeDelete && manager.catalog.activeSourceID == source
              && manager.farms[1].automaticReference == a, "ordering preserves bookmarks sources and references")
        let finalReload = FarmManager(defaults: defaults)
        check(finalReload.visibleFarms().map(\.identity) == [thirdIdentity, firstIdentity, reusedIdentity], "final order and deletion persist together")
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
        try hiddenTests()
        print("Passed \(checks) manager checks")
    }
    static func hiddenTests() throws {
        let suite = "HiddenFarmTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = FarmPresentationSession()
        let manager = FarmManager(defaults: defaults)
        manager.catalog.selectSource(path: "/synthetic/hidden", bookmark: Data([1]))
        let source = manager.catalog.activeSourceID!
        let now = Date()
        let ticks = TrackerClock.ticksAtUnixEpoch + Int64(now.timeIntervalSince1970) * 10_000_000
        let reference = SaveReference(gameTime: 100, savedTicks: ticks, nextBoundary: 500, seasonIndex: 0, sourceName: "farm_0_0.data", saveVersion: 347)
        let metadata = (0..<4).map { FT2FarmMetadata(slotIndex: $0 * 16, creationTime: ticks - 10_000_000, name: "Farm \($0)") }
        func reading(_ m: FT2FarmMetadata) -> FarmReading { FarmReading(metadata: m, reference: reference, message: "") }
        manager.catalog.merge(metadata.map(reading), sourceID: source)
        let ids = manager.knownFarms.map { $0.identity! }
        let unchanged = manager.farms[1]
        check(manager.setHidden(true, identity: ids[1]), "hide exact identity")
        var expected = unchanged; expected.hidden = true
        check(manager.farms[1] == expected, "hide changes only preference")
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == [ids[0], ids[2], ids[3]], "hidden excluded from presentation")
        check(manager.knownFarms.count == 4, "hidden remains known")
        let saved = defaults.data(forKey: "ft2FarmCatalog_v2")!
        check(!manager.setHidden(true, identity: ids[1]) && defaults.data(forKey: "ft2FarmCatalog_v2") == saved, "no-op preference does not rewrite")
        var managerPublishes = 0
        var sessionPublishes = 0
        let managerObservation = manager.objectWillChange.sink { managerPublishes += 1 }
        let sessionObservation = session.objectWillChange.sink { sessionPublishes += 1 }
        session.showHiddenFarms = true
        check(managerPublishes == 0 && sessionPublishes == 1, "presentation change publishes only session")
        check(defaults.data(forKey: "ft2FarmCatalog_v2") == saved, "session change does not write defaults")
        manager.catalog = manager.catalog
        check(managerPublishes == 1 && sessionPublishes == 1, "catalog publish never publishes session")
        check(session.showHiddenFarms, "catalog publish preserves presentation choice")
        withExtendedLifetime((managerObservation, sessionObservation)) {}
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).count == 4, "menu is nonpersistent")
        let reload = FarmManager(defaults: defaults)
        check(!FarmPresentationSession().showHiddenFarms && reload.farms[1].hidden, "restart restores hidden but resets menu")
        session.showHiddenFarms = false
        check(manager.moveFarm(ids[3], to: ids[0], showHiddenFarms: session.showHiddenFarms), "filtered drop succeeds")
        check(manager.knownFarms.map(\.identity) == [ids[3], ids[1], ids[0], ids[2]], "hidden position fixed during visible reorder")
        check(!manager.moveFarm(ids[1], to: ids[0], showHiddenFarms: session.showHiddenFarms), "invisible card cannot drop")
        session.showHiddenFarms = true
        check(manager.moveFarm(ids[1], to: ids[3], showHiddenFarms: session.showHiddenFarms), "shown hidden card can move")
        let order = manager.knownFarms.map(\.identity)
        let renamed = FT2FarmMetadata(slotIndex: metadata[1].slotIndex, creationTime: metadata[1].creationTime, name: "Renamed hidden farm")
        manager.catalog.merge([metadata[0], renamed, metadata[2], metadata[3]].map(reading), sourceID: source)
        check(manager.knownFarms.map(\.identity) == order && manager.farms.first { $0.identity == ids[1] }!.hidden, "rename preserves preference and order")
        manager.catalog.merge([metadata[0], metadata[2], metadata[3]].map(reading), sourceID: source)
        check(manager.farms.first { $0.identity == ids[1] }!.isInactive && manager.farms.first { $0.identity == ids[1] }!.hidden, "removed farm remains hidden")
        manager.catalog.merge(metadata.map(reading), sourceID: source, metadataVersion: 348)
        check(manager.farms.first { $0.identity == ids[1] }!.isInactive && manager.farms.first { $0.identity == ids[1] }!.hidden, "unconfirmed registry neither reactivates nor unhides")
        manager.catalog.apply(CatalogScanResult(readings: nil, message: "invalid future", refreshedBookmark: nil, metadataVersion: 349, metadataRejected: true), sourceID: source)
        check(manager.farms.first { $0.identity == ids[1] }!.hidden, "parse failure preserves preference")
        manager.catalog.merge(metadata.map(reading), sourceID: source)
        check(!manager.farms.first { $0.identity == ids[1] }!.isInactive && manager.farms.first { $0.identity == ids[1] }!.hidden, "reactivation preserves hidden")
        let reused = FT2FarmMetadata(slotIndex: metadata[1].slotIndex, creationTime: metadata[1].creationTime + 1, name: "New incarnation")
        manager.catalog.merge([metadata[0], reused, metadata[2], metadata[3]].map(reading), sourceID: source)
        let newFarm = manager.farms.last!
        check(newFarm.identity != ids[1] && !newFarm.hidden, "slot reuse is a new visible identity appended")
        check(manager.farms.first { $0.identity == ids[1] }!.hidden, "slot reuse preserves old hidden record")
        check(manager.removeInactiveFarm(identity: ids[1]) && !manager.farms.contains { $0.identity == ids[1] }, "delete removes hidden record completely")
        check(manager.farms.contains { $0.identity == newFarm.identity }, "delete leaves reused identity intact")
        let restored = FarmManager(defaults: defaults)
        check(restored.knownFarms.map(\.identity) == manager.knownFarms.map(\.identity), "filtered custom order persists")
        var oldJSON = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        var oldFarms = oldJSON["farms"] as! [[String: Any]]
        for i in oldFarms.indices { oldFarms[i].removeValue(forKey: "hidden") }
        oldJSON["farms"] = oldFarms
        let migrated = FarmCatalog.restored(current: try JSONSerialization.data(withJSONObject: oldJSON), now: now)
        check(migrated.farms.count == 4 && migrated.farms.allSatisfy { !$0.hidden }, "missing hidden migrates as false without data loss")
        check(migrated.farms.map(\.identity) == ids && migrated.farms.allSatisfy { $0.automaticReference == reference }, "migration retains references and identities")
        var navigation = FarmNavigation()
        let all = migrated.knownFarms
        check(navigation.detail(in: []) == nil, "no visible farms never auto opens hidden")
        check(navigation.detail(in: [all[0]])?.identity == ids[0], "one visible farm auto detail")
        check(navigation.detail(in: all) == nil, "multiple visible farms begin overview")
        navigation.open(ids[0])
        check(navigation.detail(in: [], knownFarms: all)?.identity == ids[0], "open detail survives hiding all and menu toggle")
        check(navigation.detail(in: [all[1]], knownFarms: all)?.identity == ids[0], "open detail never changes to remaining farm")
        navigation.back()
        check(navigation.detail(in: [all[1]], knownFarms: all) == nil && navigation.showsOverview, "back explicitly shows overview even with one remaining")
        navigation.reset()
        check(navigation.detail(in: [all[1]], knownFarms: all) == nil, "source reset retains overview for multiple known farms")
        navigation.open(ids[0])
        check(navigation.detail(in: [all[1]], knownFarms: [all[1]]) == nil, "deleted or other-source identity cannot resolve")
        var menuNavigation = FarmNavigation()
        let automaticHiddenDetail = menuNavigation.detail(in: [all[0]], knownFarms: [all[0]])!
        menuNavigation.open(automaticHiddenDetail.identity!)
        check(menuNavigation.detail(in: [], knownFarms: all)?.identity == ids[0], "menu handoff preserves automatically opened hidden singleton")
        check(manager.setHidden(true, identity: newFarm.identity!), "hide new incarnation independently")
        session.showHiddenFarms = false
        let beforeShow = manager.knownFarms.map(\.identity)
        check(manager.setHidden(false, identity: newFarm.identity!) && manager.knownFarms.map(\.identity) == beforeShow, "unhide preserves catalog position")
        check(!manager.setHidden(true, identity: ids[1]), "deleted identity cannot be updated")
        for farm in manager.knownFarms { manager.setHidden(true, identity: farm.identity!) }
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).isEmpty && !manager.knownFarms.isEmpty, "all hidden distinguishes empty registry from empty presentation")
        session.showHiddenFarms = true
        check(manager.visibleFarms(showHiddenFarms: session.showHiddenFarms).map(\.identity) == manager.knownFarms.map(\.identity), "menu restores all cards in catalog order")

        // Restart with every visible/hidden combination, using actual catalog persistence.
        for count in 0...4 {
            for hiddenMask in 0..<(1 << count) {
                var initialCatalog = migrated
                initialCatalog.farms = Array(all.prefix(count))
                for index in initialCatalog.farms.indices {
                    initialCatalog.farms[index].hidden = hiddenMask & (1 << index) != 0
                }
                defaults.set(try JSONEncoder().encode(initialCatalog), forKey: "ft2FarmCatalog_v2")
                let restarted = FarmManager(defaults: defaults)
                let restartedSession = FarmPresentationSession()
                let displayed = restarted.visibleFarms(showHiddenFarms: restartedSession.showHiddenFarms)
                let expected = count == 1 && hiddenMask == 0 ? all[0].identity : nil
                var initialNavigation = FarmNavigation()
                check(initialNavigation.detail(in: displayed, knownFarms: restarted.knownFarms,
                                               routingFarms: restarted.catalog.farms)?.identity == expected,
                      "restart navigation: \(count) known, hidden mask \(hiddenMask)")
                check(initialNavigation.shouldSuppressInitialControlFocus(
                    in: displayed, knownFarms: restarted.knownFarms, routingFarms: restarted.catalog.farms)
                      == (!displayed.isEmpty && count > 1),
                      "overview startup focus protection: \(count) known, hidden mask \(hiddenMask)")
                check(!restartedSession.showHiddenFarms && restarted.knownFarms.count == count,
                      "restart keeps known catalog and resets only session visibility")
                initialNavigation.reset()
                check(initialNavigation.detail(in: displayed, knownFarms: restarted.knownFarms)?.identity == expected,
                      "central reset follows same rule as initial navigation")
                restartedSession.showHiddenFarms = true
                check(FarmNavigation().detail(in: restarted.visibleFarms(showHiddenFarms: restartedSession.showHiddenFarms),
                                              knownFarms: restarted.knownFarms)?.identity == (count == 1 ? all[0].identity : nil),
                      "show-hidden menu keeps multiple known farms in overview")
                if let target = restarted.knownFarms.last?.identity {
                    initialNavigation.open(target)
                    check(initialNavigation.detail(in: displayed, knownFarms: restarted.knownFarms)?.identity == target,
                          "explicit detail/hidden reminder bypasses automatic rule")
                    check(!initialNavigation.shouldSuppressInitialControlFocus(in: displayed, knownFarms: restarted.knownFarms),
                          "explicit detail preserves normal focus behavior")
                    initialNavigation.back()
                    check(initialNavigation.detail(in: displayed, knownFarms: restarted.knownFarms) == nil,
                          "back preserves explicit overview")
                    check(initialNavigation.shouldSuppressInitialControlFocus(in: displayed, knownFarms: restarted.knownFarms)
                          == !displayed.isEmpty, "overview return uses focus protection even for a single card")
                }
            }
        }

    }

}
