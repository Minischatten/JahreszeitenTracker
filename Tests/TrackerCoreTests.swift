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
            ("version", document(version: 348)), ("season", document(s: 4)),
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
            check(Set(readings.map { $0.metadata.slotIndex }).isSuperset(of: [0, 16]), "live nonconsecutive farms")
            check(readings.allSatisfy { $0.reference != nil }, "live farm references")
            for (file, hash) in zip(files, hashes) {
                check(try SHA256.hash(data: FT2SaveAccess.readOnlySnapshot(file)) == hash, "live files unchanged")
            }
            print("Read-only live catalog: \(readings.map { "\($0.metadata.slotIndex): \($0.metadata.name)" })")
        }
        print("Passed \(checks) checks")
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
        rejects("metadata version") { _ = try FT2MetadataParser.parse(metadataDocument([], version: 348)) }
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
        catalog.farms[0].manualCorrection = 7
        let firstReference = catalog.farms[0].automaticReference
        try metadataDocument([(0, created, "Gleicher Name"), (16, created, "Gleicher Name")]).write(to: mlk)
        catalog.merge(try FT2SaveAccess.catalog(in: temp, now: Date()), sourceID: source)
        check(catalog.farms.count == 2 && catalog.farms[0].manualCorrection == 7 && catalog.farms[0].automaticReference == firstReference, "rename preserves correction and reference")
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
        let previousIdentity = catalog.farms[0].identity
        catalog.selectSource(path: temp.path, bookmark: Data([2]))
        check(catalog.activeSourceID == source && catalog.farms[0].identity == previousIdentity, "source reselect keeps identity")
        catalog.selectSource(path: missing.path, bookmark: Data([3]))
        catalog.merge([FarmReading(metadata: metadata[0], reference: reference, message: "")], sourceID: catalog.activeSourceID!)
        check(catalog.farms.count == 4, "different source keeps same slot separate")
    }
}

extension Data {
    func mapData(_ transform: (UInt8) -> UInt8) -> Data { Data(map(transform)) }
}
