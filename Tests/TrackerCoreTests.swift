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
        print("Passed \(checks) checks")
    }
}
