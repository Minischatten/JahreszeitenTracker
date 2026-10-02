import Foundation
import CryptoKit
import zlib

@main
struct TrackerCoreTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Should reject: \(message)") }
        catch { checks += 1 }
    }
    static func integer(_ value: Int64) -> [UInt8] {
        [0xd3] + (0..<8).reversed().map { UInt8(truncatingIfNeeded: UInt64(bitPattern: value) >> ($0 * 8)) }
    }
    static func document(g: Int64 = 75_695_793, ticks: Int64 = 639_263_913_480_000_000,
                         b: Int64 = 75_696_750, s: Int64 = 0, version: Int64 = 347) -> [UInt8] {
        [0xc1, 21] + integer(s) + [16] + integer(ticks) + [0] + integer(version)
            + [18] + integer(b) + [15] + integer(g) + [0xc8]
    }
    static func gzip(_ bytes: [UInt8]) -> Data {
        var stream = z_stream()
        precondition(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
                                  ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        return bytes.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            var out = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))))
            out.withUnsafeMutableBytes { buffer in
                stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(buffer.count)
                precondition(deflate(&stream, Z_FINISH) == Z_STREAM_END)
            }
            return Data(out.prefix(Int(stream.total_out)))
        }
    }
    static func main() throws {
        try versionCompatibilityTests()
        let reference = try FT2SaveParser.parse(gzip(document()), sourceName: "fixture")
        check(reference.state(at: reference.savedAt) == SeasonState(seasonIndex: 0, remaining: 957), "initial state")
        check(reference.state(at: reference.savedAt.addingTimeInterval(957)) == SeasonState(seasonIndex: 1, remaining: 1020), "exact boundary")
        check(reference.state(at: reference.savedAt.addingTimeInterval(3576)) == SeasonState(seasonIndex: 3, remaining: 441), "offline measured result")
        for cycles in [0, 1, 100, 100_000] {
            check(reference.state(at: reference.savedAt.addingTimeInterval(Double(cycles) * 4080)) == SeasonState(seasonIndex: 0, remaining: 957), "long intervals")
        }
        check(reference.state(at: reference.savedAt.addingTimeInterval(-64)) == SeasonState(seasonIndex: 3, remaining: 1), "negative elapsed")
        for seconds in [-1020.0, -1, 0, 1, 957, 1020, 1_000_000] {
            let state = reference.state(at: reference.savedAt.addingTimeInterval(seconds))
            check((0..<4).contains(state.seasonIndex) && state.remaining > 0 && state.remaining <= 1020, "bounds")
        }
        check(ReferenceUpdate.decision(candidate: reference, previous: nil) == .accept, "first import")
        check(ReferenceUpdate.decision(candidate: reference, previous: reference) == .unchanged, "equal import")
        let old = SaveReference(gameTime: reference.gameTime, savedTicks: reference.savedTicks - 10_000_000,
                                nextBoundary: reference.nextBoundary, seasonIndex: 0, sourceName: "old")
        check(ReferenceUpdate.decision(candidate: old, previous: reference) == .older, "rollback refused")
        check(ReferenceUpdate.decision(candidate: reference, previous: old) == .accept, "newer accepted")
        let conflict = SaveReference(gameTime: reference.gameTime + 1, savedTicks: reference.savedTicks,
                                     nextBoundary: reference.nextBoundary, seasonIndex: 0, sourceName: "conflict")
        check(ReferenceUpdate.decision(candidate: conflict, previous: reference) == .conflict, "conflict refused")
        let encoded = try JSONEncoder().encode(reference)
        check(try JSONDecoder().decode(SaveReference.self, from: encoded) == reference, "reference persistence")
        for (label, bytes) in [
            ("older unknown version", document(version: 346)), ("season", document(s: 4)),
            ("past boundary", document(b: 75_695_793)), ("far boundary", document(b: 75_696_814)),
            ("missing field", [0xc1, 0] + integer(347) + [0xc8]),
            ("truncated structure", Array(document().dropLast())),
            ("duplicate field", Array(document().dropLast()) + [15] + integer(0) + [0xc8]),
            ("unsupported type", Array(document().dropLast()) + [40, 0xd9, 0, 0xc8]),
            ("trailing document", document() + [0]),
            ("depth", Array(document().dropLast()) + [40] + Array(repeating: 0xc7, count: 65) + Array(repeating: 0xc8, count: 66))
        ] { rejects(label) { _ = try FT2SaveParser.parse(gzip(bytes), sourceName: label) } }
        let good = gzip(document())
        rejects("truncated gzip") { _ = try FT2SaveParser.parse(good.dropLast(), sourceName: "bad") }
        var corrupt = good; corrupt[corrupt.count - 8] ^= 1
        rejects("CRC") { _ = try FT2SaveParser.parse(corrupt, sourceName: "bad") }
        rejects("gzip trailing") { _ = try FT2SaveParser.parse(good + Data([0]), sourceName: "bad") }
        rejects("compressed limit") { _ = try FT2SaveParser.parse(Data(repeating: 0, count: FT2SaveParser.maximumCompressedSize + 1), sourceName: "bad") }
        rejects("future date") { _ = try FT2SaveParser.parse(good, sourceName: "bad", now: reference.savedAt.addingTimeInterval(-301)) }

        // Fixtures below are synthetic and written ONLY under a fresh temporary directory.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("FT2TrackerTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        try good.write(to: temp.appendingPathComponent("farm_0_0.data"))
        try gzip(document(ticks: reference.savedTicks + 10_000_000)).write(to: temp.appendingPathComponent("farm_0_5.data"))
        try gzip(document(ticks: reference.savedTicks + 20_000_000)).write(to: temp.appendingPathComponent("farm_0_4.data.bak"))
        let newest = try FT2SaveAccess.newest(in: temp, slot: 0, now: Date())
        check(newest?.savedTicks == reference.savedTicks + 10_000_000, "embedded timestamp ordering / .bak excluded")
        check(try FT2SaveAccess.newest(in: temp, slot: 1, now: Date()) == nil, "slot isolation")
        try Data([0, 1]).write(to: temp.appendingPathComponent("farm_0_5.data"))
        check(try FT2SaveAccess.newest(in: temp, slot: 0, now: Date())?.savedTicks == reference.savedTicks, "invalid candidate fallback")
        try gzip(document(g: reference.gameTime + 1)).write(to: temp.appendingPathComponent("farm_0_1.data"))
        rejects("equal timestamp conflict") { _ = try FT2SaveAccess.newest(in: temp, slot: 0, now: Date()) }
        try FileManager.default.createSymbolicLink(at: temp.appendingPathComponent("farm_1_0.data"),
                                                  withDestinationURL: temp.appendingPathComponent("farm_0_0.data"))
        rejects("symlink") { _ = try FT2SaveAccess.readOnlySnapshot(temp.appendingPathComponent("farm_1_0.data")) }

        // Optional read-only verification against all supplied historical measurement files.
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)!
            var measured = 0
            for case let file as URL in enumerator where file.lastPathComponent.hasPrefix("farm_0_") && file.pathExtension == "data" {
                let before = SHA256.hash(data: try FT2SaveAccess.readOnlySnapshot(file))
                let parsed = try FT2SaveParser.parse(FT2SaveAccess.readOnlySnapshot(file), sourceName: file.lastPathComponent)
                check(parsed.nextBoundary % 1020 == 510, "measured season lattice")
                check(parsed.state(at: parsed.savedAt).remaining == Double(parsed.nextBoundary - parsed.gameTime), "measured rest time")
                let after = SHA256.hash(data: try FT2SaveAccess.readOnlySnapshot(file))
                check(before == after, "original save unchanged")
                measured += 1
            }
            print("Read-only measurement files checked: \(measured)")
        }
        try catalogTests(reference: reference)
        if CommandLine.arguments.count > 2 {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let files = [root.appendingPathComponent("farms.mlk")] + (try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("farms"), includingPropertiesForKeys: nil)).filter { $0.pathExtension == "data" }
            let hashes = try files.map { SHA256.hash(data: try FT2SaveAccess.readOnlySnapshot($0)) }
            let readings = try FT2SaveAccess.catalog(in: root, now: Date())
            let liveMetadata = try FT2MetadataParser.parse(FT2SaveAccess.readOnlySnapshot(root.appendingPathComponent("farms.mlk")))
            check(readings.map(\.metadata) == liveMetadata, "live catalog matches current registry rather than historical slot assumptions")
            check(readings.allSatisfy { reading in
                guard let reference = reading.reference else { return true }
                return reference.savedTicks >= reading.metadata.creationTime
            }, "live references do not predate farm creation")
            for (file, hash) in zip(files, hashes) {
                check(try SHA256.hash(data: FT2SaveAccess.readOnlySnapshot(file)) == hash, "live files unchanged")
            }
            print("Read-only live catalog: \(readings.map { "\($0.metadata.slotIndex): \($0.metadata.name)" })")
        }
        print("Passed \(checks) checks")
    }

    static func versionCompatibilityTests() throws {
        let now = Date()
        let base = try FT2SaveParser.parse(gzip(document()), sourceName: "farm_0_0.data", now: now)
        let future = try FT2SaveParser.parse(gzip(document(version: 348)), sourceName: "farm_0_0.data", now: now)
        check(base.version == 347 && future.version == 348, "version provenance")
        check(base.state(at: now) == future.state(at: now), "version does not change timing")
        let extra = Array(document(version: 348).dropLast()) + [40, 0xc7, 1, 0xa1, 65, 0xc8, 0xc8]
        check(try FT2SaveParser.parse(gzip(extra), sourceName: "extra").version == 348, "unknown fields with supported types skipped")
        for bytes in [[0xc1, 0] + integer(348) + [15, 0xca, 0, 0, 0, 0, 0xc8], document(s: 4, version: 348),
                      Array(document(version: 348).dropLast()) + [40, 0xd9, 0, 0xc8],
                      [0xc1, 0] + integer(348) + [0xc8]] {
            rejects("future structural validation") { _ = try FT2SaveParser.parse(gzip(bytes), sourceName: "bad") }
        }
        let wrongTypeBeforeVersion: [UInt8] = [0xc1, 21, 0xca, 0, 0, 0, 0, 0] + integer(348) + [0xc8]
        do { _ = try FT2SaveParser.parse(gzip(wrongTypeBeforeVersion), sourceName: "wrong type"); fatalError("wrong type accepted") }
        catch { check((error as? FT2VersionError)?.version == 348, "version still recognized after earlier scalar type error") }
        let legacy = SaveReference(gameTime: base.gameTime, savedTicks: base.savedTicks, nextBoundary: base.nextBoundary,
                                   seasonIndex: base.seasonIndex, sourceName: "legacy")
        let legacyData = try JSONEncoder().encode(legacy)
        check(try JSONDecoder().decode(SaveReference.self, from: legacyData).version == 347, "legacy reference defaults to confirmed 347")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FT2VersionTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let areas = root.appendingPathComponent("farms")
        try FileManager.default.createDirectory(at: areas, withIntermediateDirectories: false)
        let created = base.savedTicks - 10_000_000
        let mlk = root.appendingPathComponent("farms.mlk")
        let oldFile = areas.appendingPathComponent("farm_0_0.data")
        let newFile = areas.appendingPathComponent("farm_0_1.data")
        try metadataDocument([(0, created, "Original")]).write(to: mlk)
        try gzip(document()).write(to: oldFile)
        var catalog = FarmCatalog()
        catalog.selectSource(path: root.path, bookmark: Data([1]))
        let source = catalog.activeSourceID!
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        let original = catalog.farms[0]
        check(FarmSyncState.forFarm(original) == .synchronized, "347 behavior unchanged")
        // A newer incompatible candidate cannot be hidden by an old valid area.
        let badBytes = gzip(document(ticks: base.savedTicks + 10_000_000, s: 4, version: 348))
        try badBytes.write(to: newFile)
        let beforeHash = SHA256.hash(data: try Data(contentsOf: newFile))
        let rejected = try FT2SaveAccess.catalogSnapshot(in: root, now: now)
        catalog.apply(rejected, sourceID: source)
        check(catalog.farms[0].registered == true && catalog.farms[0].automaticReference == original.automaticReference, "mixed invalid preserves reference and registration")
        check(FarmSyncState.forFarm(catalog.farms[0]) == .lastStandNewVersion, "old valid area cannot hide future failure")
        check(SHA256.hash(data: try Data(contentsOf: newFile)) == beforeHash, "scan never writes source")
        let rejectedFarm = catalog.farms[0]
        var missingWithWarning = catalog
        missingWithWarning.merge([], sourceID: source, metadataVersion: 348)
        check(missingWithWarning.farms[0].compatibility?.rejectedVersions == rejectedFarm.compatibility?.rejectedVersions
              && FarmSyncState.forFarm(missingWithWarning.farms[0]) == .lastStandNewVersion,
              "non-authoritative missing entry cannot clear prior plot failure")
        var changedDuringRead = catalog
        changedDuringRead.apply(FT2SaveAccess.failedScan(FT2Error.invalid("Metadaten während Scan verändert")), sourceID: source)
        check(changedDuringRead.farms[0].registered == true && changedDuringRead.farms[0].automaticReference == rejectedFarm.automaticReference,
              "changed metadata snapshot cannot delete registration or reference")
        var fresh = FarmCatalog(); fresh.selectSource(path: root.path, bookmark: Data([2]))
        try Data([0]).write(to: oldFile)
        fresh.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: fresh.activeSourceID!)
        check(fresh.farms[0].automaticReference == nil && FarmSyncState.forFarm(fresh.farms[0]) == .waitingNewVersion, "all invalid without reference has no countdown")
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(catalog.farms[0].automaticReference == original.automaticReference && !catalog.farms[0].isInactive, "all invalid keeps existing state")
        try gzip(document(ticks: base.savedTicks + 20_000_000, version: 348)).write(to: newFile)
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(catalog.farms[0].automaticReference?.version == 348 && FarmSyncState.forFarm(catalog.farms[0]) == .unconfirmedVersion, "newest valid future reference accepted with warning")
        let acceptedFuture = catalog.farms[0].automaticReference
        check(FarmSyncState.forFarm(catalog.farms[0], confirmedVersions: [347, 348]) == .synchronized, "central confirmation reclassifies trust")
        check(catalog.farms[0].versionExplanation(isGerman: true)?.contains("348") == true, "detail includes dynamic version")
        // Exact known identity can use a new plot; new identities and renames cannot merge.
        try metadataDocument([(0, created, "Changed"), (16, created, "New")], version: 348).write(to: mlk)
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(catalog.farms.count == 1 && catalog.farms[0].id == original.id && catalog.farms[0].name == "Original", "unconfirmed metadata cannot create or rename")
        check(catalog.sources[0].metadataNotice?.deferredFarms == 1, "new identities deferred centrally")
        try metadataDocument([], version: 348).write(to: mlk)
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(catalog.farms[0].registered == true && catalog.farms[0].automaticReference == acceptedFuture, "empty unconfirmed registry never deletes")
        var inactive = catalog; inactive.farms[0].registered = false
        try metadataDocument([(0, created, "Changed")], version: 348).write(to: mlk)
        inactive.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(inactive.farms[0].isInactive, "unconfirmed registry cannot reactivate")
        try metadataDocument([(0, created + 100_000_000, "Reused")], version: 348).write(to: mlk)
        catalog.apply(try FT2SaveAccess.catalogSnapshot(in: root, now: now), sourceID: source)
        check(catalog.farms.count == 1 && catalog.farms[0].identity == original.identity, "unconfirmed reused slot cannot replace identity")
        // A complete higher-version JSON with malformed farm fields retains its version in the error.
        let badMetadata = gzip(Array("{version:348,farms:[{slotIndex:0,farm:{name:123,creation_time:\(created)}}]}".utf8)).mapData { ($0 &- 31) ^ 255 }
        try badMetadata.write(to: mlk)
        do { _ = try FT2SaveAccess.catalogSnapshot(in: root, now: now); fatalError("invalid metadata accepted") }
        catch { catalog.apply(FT2SaveAccess.failedScan(error), sourceID: source) }
        check(catalog.farms[0].registered == true && catalog.farms[0].automaticReference == acceptedFuture, "bad metadata retains all identity and reference data")
        check(FarmSyncState.forFarm(catalog.farms[0]) == .lastStandNewVersion, "bad metadata version warning")
        var confirmedButStillInvalid = catalog.farms[0]
        confirmedButStillInvalid.compatibility = FarmCompatibility(metadataVersion: 347, metadataRejected: true)
        confirmedButStillInvalid.automaticReference = base
        check(confirmedButStillInvalid.versionExplanation(isGerman: true)?.contains("347") == true,
              "confirmation cannot hide version number of a retained invalid metadata report")
        let encoded = try JSONEncoder().encode(catalog)
        let restored = FarmCatalog.restored(current: encoded, now: now)
        check(restored.farms[0].automaticReference == acceptedFuture && restored.farms[0].compatibility == catalog.farms[0].compatibility, "trust and reference persist")
        check(FarmSyncState.forFarm(restored.farms[0]) == .lastStandNewVersion, "restart cannot turn warning green")
        // Release confirmation alone does not mutate registration; a fresh complete scan does.
        try metadataDocument([(16, created, "New")], version: 348).write(to: mlk)
        let confirmedScan = try FT2SaveAccess.catalogSnapshot(in: root, now: now)
        catalog.apply(confirmedScan, sourceID: source, confirmedVersions: [347, 348])
        check(catalog.farms.count == 2 && catalog.farms[0].isInactive && catalog.farms[1].registered == true, "fresh confirmed registry authoritatively merges")
        check(catalog.sources[0].metadataNotice == nil, "confirmed fresh scan clears catalog notice")
        var empty = FarmCatalog(); empty.selectSource(path: root.path, bookmark: Data([3]))
        empty.apply(confirmedScan, sourceID: empty.activeSourceID!)
        check(empty.farms.isEmpty, "entirely new unconfirmed catalog creates no persistent identity or countdown")
        // Unknown version when gzip is corrupt must not manufacture a version number.
        let unknown = FT2SaveAccess.failedScan(FT2Error.invalid("Gzip"))
        check(unknown.metadataVersion == nil && !unknown.metadataRejected, "unknown format never guesses a version")
        catalog.apply(unknown, sourceID: source)
        check(catalog.farms.count == 2, "unknown parse failure is not empty registry")
        try metadataDocument([(0, created, "Original")]).write(to: mlk)
        try gzip(document()).write(to: oldFile)
        try gzip(document(g: base.gameTime + 1, version: 348)).write(to: newFile)
        let conflicting = try FT2SaveAccess.catalogSnapshot(in: root, now: now)
        check(conflicting.readings?[0].reference == nil && conflicting.readings?[0].rejectedVersions == [348], "mixed equal-time conflict retains future warning")
        let conflictingFuture = SaveReference(gameTime: base.gameTime + 1, savedTicks: base.savedTicks, nextBoundary: base.nextBoundary,
            seasonIndex: base.seasonIndex, sourceName: "conflict", saveVersion: 348)
        var directConflict = FarmCatalog(); directConflict.selectSource(path: root.path, bookmark: Data([4]))
        let directSource = directConflict.activeSourceID!
        let directMetadata = FT2FarmMetadata(slotIndex: 0, creationTime: created, name: "Original")
        directConflict.merge([FarmReading(metadata: directMetadata, reference: base, message: "")], sourceID: directSource)
        directConflict.merge([FarmReading(metadata: directMetadata, reference: conflictingFuture, message: "")], sourceID: directSource)
        check(directConflict.farms[0].automaticReference == base && FarmSyncState.forFarm(directConflict.farms[0]) == .lastStandNewVersion,
              "future reference conflicts with persisted state must warn rather than overwrite")
        let extraMetadata = gzip(Array("{version:348,farms:[],newFeature:{value:[true,1,\"text\"]}}".utf8)).mapData { ($0 &- 31) ^ 255 }
        check(try FT2MetadataParser.parseDocument(extraMetadata).version == 348, "unknown valid metadata properties skipped")
        // A confirmed newest save may supersede a definitively older valid probe.
        try gzip(document(ticks: base.savedTicks + 30_000_000)).write(to: oldFile)
        try gzip(document(version: 348)).write(to: newFile)
        let newerConfirmed = try FT2SaveAccess.catalogSnapshot(in: root, now: now)
        check(newerConfirmed.readings?[0].reference?.version == 347 && newerConfirmed.readings?[0].observedPlotVersion == 347,
              "newest validated timestamp wins over version number")
        // Equal-time equivalent data carry the higher-version observation.
        try gzip(document(ticks: base.savedTicks + 30_000_000, version: 348)).write(to: newFile)
        let equalEquivalent = try FT2SaveAccess.catalogSnapshot(in: root, now: now)
        check(equalEquivalent.readings?[0].observedPlotVersion == 348 && equalEquivalent.readings?[0].reference?.version == 348,
              "equivalent mixed saves cannot silently lose unconfirmed provenance")
        // Date plausibility, creation-time ownership, duplicates and mutation safety stay mandatory.
        rejects("future save time") { _ = try FT2SaveParser.parse(gzip(document(version: 348)), sourceName: "future", now: base.savedAt.addingTimeInterval(-301)) }
        rejects("future metadata duplicate") { _ = try FT2MetadataParser.parse(metadataDocument([(0, created, "A"), (0, created, "B")], version: 348)) }
        check(try FT2SaveAccess.newest(in: areas, slot: 0, now: now, createdAt: base.savedTicks + 100_000_000) == nil, "new identity refuses leftovers")
    }

    static func metadataDocument(_ farms: [(Int, Int64, String)], version: Int = 347) throws -> Data {
        let entries = try farms.map { slot, created, name in
            let escaped = String(decoding: try JSONEncoder().encode(name), as: UTF8.self)
            return "{slotIndex:\(slot),farm:{name:\(escaped),creation_time:\(created)}}"
        }.joined(separator: ",")
        return gzip(Array("{version:\(version),farms:[\(entries)]}".utf8)).mapData { ($0 &- 31) ^ 255 }
    }

    static func catalogTests(reference: SaveReference) throws {
        let created = reference.savedTicks - 100_000_000
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("FT2CatalogTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("farms"), withIntermediateDirectories: true)
        let areas = temp.appendingPathComponent("farms")
        let mlk = temp.appendingPathComponent("farms.mlk")
        let originalName = "  Farm mit {name: \\\"Text\\\"} und 🌱  "
        let fixture = try metadataDocument([(0, created, originalName), (16, created, "Testfarm")])
        try fixture.write(to: mlk)
        let metadata = try FT2MetadataParser.parse(fixture)
        check(metadata.map(\.slotIndex) == [0, 16], "metadata IDs")
        check(metadata[0].creationTime == created && metadata[0].name == originalName, "exact ticks and untouched strings")
        rejects("older metadata version") { _ = try FT2MetadataParser.parse(metadataDocument([], version: 346)) }
        rejects("metadata duplicate slot") { _ = try FT2MetadataParser.parse(metadataDocument([(0, created, "A"), (0, created, "B")])) }
        rejects("metadata truncation") { _ = try FT2MetadataParser.parse(fixture.dropLast()) }
        let duplicate = gzip(Array("{version:347,farms:[],farms:[]}".utf8)).mapData { ($0 &- 31) ^ 255 }
        rejects("metadata duplicate property") { _ = try FT2MetadataParser.parse(duplicate) }
        let fakeNameKey = try metadataDocument([(0, created, "a,b:name \" \\ \n")])
        check(try FT2MetadataParser.parse(fakeNameKey)[0].name == "a,b:name \" \\ \n", "quoted strings preserved")
        for plot in 0..<6 {
            try gzip(document(ticks: reference.savedTicks + Int64(plot) * 10_000_000)).write(to: areas.appendingPathComponent("farm_0_\(plot).data"))
        }
        try gzip(document(g: 260, b: 510, s: 0)).write(to: areas.appendingPathComponent("farm_16_0.data"))
        var readings = try FT2SaveAccess.catalog(in: temp, now: Date())
        check(readings.count == 2 && readings[0].reference?.sourceName == "farm_0_5.data", "six areas newest")
        check(readings[1].reference?.gameTime == 260, "one area independent")
        try gzip(document(g: 380, ticks: reference.savedTicks + 120_000_000, b: 510)).write(to: areas.appendingPathComponent("farm_16_1.data"))
        readings = try FT2SaveAccess.catalog(in: temp, now: Date())
        check(readings[1].reference?.sourceName == "farm_16_1.data", "new area automatically discovered")
        var catalog = FarmCatalog()
        catalog.selectSource(path: temp.path, bookmark: Data([1]))
        let source = catalog.activeSourceID!
        catalog.merge(readings, sourceID: source)
        check(catalog.farms.count == 2 && catalog.farms[0].automaticReference?.gameTime != catalog.farms[1].automaticReference?.gameTime, "independent references")
        check(catalog.farms[0].name == originalName && catalog.farms[0].displayName == originalName.trimmingCharacters(in: .whitespacesAndNewlines), "display-only trimming")
        let firstReference = catalog.farms[0].automaticReference
        try metadataDocument([(0, created, "Gleicher Name"), (16, created, "Gleicher Name")]).write(to: mlk)
        catalog.merge(try FT2SaveAccess.catalog(in: temp, now: Date()), sourceID: source)
        check(catalog.farms.count == 2 && catalog.farms[0].automaticReference == firstReference, "rename preserves reference")
        check(catalog.farms[0].name == catalog.farms[1].name && catalog.farms[0].identity != catalog.farms[1].identity, "duplicate names")
        try Data([0]).write(to: areas.appendingPathComponent("farm_16_1.data"))
        readings = try FT2SaveAccess.catalog(in: temp, now: Date())
        check(readings[1].reference?.sourceName == "farm_16_0.data", "damaged newest falls back")
        catalog.merge(readings, sourceID: source)
        check(catalog.farms[1].automaticReference?.sourceName == "farm_16_1.data", "older fallback never rolls reference back")
        try metadataDocument([(0, created, "Gleicher Name"), (16, reference.savedTicks + 200_000_000, "Neue Farm")]).write(to: mlk)
        catalog.merge(try FT2SaveAccess.catalog(in: temp, now: Date()), sourceID: source)
        check(catalog.farms.count == 3 && catalog.farms[1].available == false, "reused slot creates new identity retains old")
        check(catalog.farms[2].automaticReference == nil, "reused slot rejects leftover areas")
        try metadataDocument([]).write(to: mlk)
        catalog.merge(try FT2SaveAccess.catalog(in: temp, now: Date()), sourceID: source)
        check(catalog.farms.count == 3 && catalog.farms.allSatisfy { $0.available == false }, "missing registry retains all")
        let retained = catalog.farms[0].automaticReference
        try Data([0]).write(to: mlk)
        rejects("unreadable metadata") { _ = try FT2SaveAccess.catalog(in: temp, now: Date()) }
        check(catalog.farms[0].automaticReference == retained, "metadata failure cannot destroy reference")
        let missing = temp.appendingPathComponent("missing")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
        rejects("missing metadata") { _ = try FT2SaveAccess.catalog(in: missing, now: Date()) }
        try metadataDocument([(7, created, "Ohne Bereich")]).write(to: missing.appendingPathComponent("farms.mlk"))
        check(try FT2SaveAccess.catalog(in: missing, now: Date())[0].reference == nil, "registered without areas")
        try FileManager.default.createDirectory(at: missing.appendingPathComponent("farms"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: missing.appendingPathComponent("farms/farm_7_0.data"), withDestinationURL: areas.appendingPathComponent("farm_0_0.data"))
        check(try FT2SaveAccess.catalog(in: missing, now: Date())[0].reference == nil, "catalog refuses symlink area")
        check(FarmCatalog.restored(current: nil, now: Date()).farms.isEmpty, "fresh catalog has no placeholders")
        check(FarmCatalog.restored(current: Data([0]), now: Date()).farms.isEmpty, "invalid catalog safe")
        let encoded = try JSONEncoder().encode(catalog)
        let restored = FarmCatalog.restored(current: encoded, now: Date())
        check(restored.farms.count == 3 && restored.farms[0].automaticReference == retained && restored.sources == catalog.sources, "catalog persistence")
        var archivedJSON = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        archivedJSON["legacyFarms"] = [["name": "obsolete archive"]]
        let oldCatalog = try JSONSerialization.data(withJSONObject: archivedJSON)
        let withoutArchive = FarmCatalog.restored(current: oldCatalog, now: Date())
        check(withoutArchive.farms == restored.farms && withoutArchive.sources == restored.sources
              && withoutArchive.activeSourceID == restored.activeSourceID, "existing catalog ignores legacy archive without losing active data")
        let cleanedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(withoutArchive)) as! [String: Any]
        check(cleanedJSON["legacyFarms"] == nil, "legacy archive not serialized")
        check(catalog.visibleFarms.count == 3 && catalog.visibleFarms.allSatisfy(\.isInactive), "removed farms stay visible in catalog order")
        let previousIdentity = catalog.farms[0].identity
        catalog.selectSource(path: temp.path, bookmark: Data([2]))
        check(catalog.activeSourceID == source && catalog.farms[0].identity == previousIdentity, "source reselect keeps identity")
        catalog.selectSource(path: missing.path, bookmark: Data([3]))
        catalog.merge([FarmReading(metadata: metadata[0], reference: reference, message: "")], sourceID: catalog.activeSourceID!)
        check(catalog.farms.count == 4, "different source keeps same slot separate")
        check(catalog.visibleFarms.count == 1 && FarmNavigation().detail(in: catalog.visibleFarms) != nil, "one farm forces single mode")
        let originalID = catalog.activeSourceID!
        catalog.merge([
            FarmReading(metadata: metadata[0], reference: reference, message: ""),
            FarmReading(metadata: metadata[1], reference: reference, message: "")
        ], sourceID: originalID)
        check(catalog.visibleFarms.count == 2 && FarmNavigation().detail(in: catalog.visibleFarms) == nil, "multiple farms start in overview")
        var navigation = FarmNavigation()
        navigation.open(catalog.visibleFarms[1].identity!)
        check(navigation.detail(in: catalog.visibleFarms)?.identity == catalog.visibleFarms[1].identity, "card opens exact identity")
        navigation.back()
        check(navigation.detail(in: catalog.visibleFarms) == nil, "back restores overview")
        navigation.open(FarmIdentity(sourceID: UUID(), slotIndex: 0, creationTime: 0))
        check(navigation.detail(in: catalog.visibleFarms) == nil, "missing identity safely shows overview")
        check(FarmSyncState.forFarm(catalog.visibleFarms[0]) == .synchronized, "verified reference synced")
        catalog.merge([FarmReading(metadata: metadata[0], reference: nil, message: "read error")], sourceID: originalID)
        check(catalog.visibleFarms.count == 2 && FarmSyncState.forFarm(catalog.visibleFarms[0]) == .lastStand
              && FarmSyncState.forFarm(catalog.visibleFarms[1]) == .notFound, "plot failure remains registered while missing farm stays visible")
        check(catalog.farms.contains { $0.identity?.slotIndex == 16 && $0.automaticReference != nil }, "inactive farm reference retained")
        let inactiveIdentity = catalog.visibleFarms[1].identity!
        let inactiveRecord = catalog.visibleFarms[1]
        check(FarmNavigation(openedIdentity: inactiveIdentity).detail(in: catalog.visibleFarms) == inactiveRecord,
              "inactive card opens normal detail by identity")
        check(inactiveRecord.automaticReference?.state(at: reference.savedAt.addingTimeInterval(2040)) != nil,
              "inactive countdown continues across seasons")
        let orderBeforeReturn = catalog.visibleFarms.map(\.identity)
        catalog.merge([
            FarmReading(metadata: metadata[0], reference: reference, message: ""),
            FarmReading(metadata: metadata[1], reference: reference, message: "")
        ], sourceID: originalID)
        check(catalog.visibleFarms.map(\.identity) == orderBeforeReturn
              && !catalog.visibleFarms[1].isInactive, "returning exact identity reactivates in original position")
        check(!catalog.removeInactiveFarm(identity: inactiveIdentity), "reactivated farm protected from stale delete confirmation")
        var inactiveWithoutReference = FarmData(id: 998, name: "Removed", registered: false)
        check(FarmSyncState.forFarm(inactiveWithoutReference) == .notFound, "inactive status takes priority over missing reference")
        inactiveWithoutReference.registered = nil
        check(!inactiveWithoutReference.isInactive, "unknown registration is not removal")
        var noReference = FarmData(id: 999, name: "Waiting")
        noReference.available = true
        check(FarmSyncState.forFarm(noReference) == .waiting, "registration alone not synchronization")
        for remaining in [0.1, 1, 59.9, 1018, 1019, 1020] {
            check(CountdownDisplay.seconds(remaining: remaining) == Int(min(remaining + 2, 1020)), "display compensation unchanged")
        }
        check(CountdownDisplay.text(remaining: 1020) == "17:00", "display clamp")
        check(CountdownDisplay.text(remaining: 57.9) == "00:59", "display truncation unchanged")
    }
}

extension Data {
    func mapData(_ transform: (UInt8) -> UInt8) -> Data { Data(map(transform)) }
}
