import Foundation
import zlib

/// Parses only the observed FT2 variant, not standard MessagePack.
/// Walks the entire document, retaining only the four root synchronization values.
nonisolated enum FT2SaveParser {
    static let maximumCompressedSize = 16 * 1024 * 1024
    static let maximumExpandedSize = 64 * 1024 * 1024

    static func parse(_ compressed: Data, sourceName: String, now: Date = Date()) throws -> SaveReference {
        var reader = Reader(bytes: Array(try gunzip(compressed)))
        let fields = try reader.root()
        guard let g = fields[15], let t = fields[16], let b = fields[18], let s = fields[21],
              (0..<4).contains(s) else { throw FT2Error.invalid("fehlende Synchronisationsfelder") }
        return try SaveReference(gameTime: g, savedTicks: t, nextBoundary: b,
                                 seasonIndex: Int(s), sourceName: sourceName).validated(now: now)
    }

    static func gunzip(_ input: Data) throws -> Data {
        guard input.count >= 18, input.count <= maximumCompressedSize,
              input.starts(with: [0x1f, 0x8b, 0x08]) else { throw FT2Error.invalid("Gzip-Header oder Größe") }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw FT2Error.invalid("Gzip-Initialisierung")
        }
        defer { inflateEnd(&stream) }
        return try input.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let result = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = chunk.count - Int(stream.avail_out)
                guard output.count + count <= maximumExpandedSize else { throw FT2Error.invalid("entpackte Größe") }
                output.append(contentsOf: chunk.prefix(count))
                if result == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw FT2Error.invalid("Daten hinter Gzip-Ende") }
                    return output
                }
                guard result == Z_OK, count > 0 else { throw FT2Error.invalid("unvollständiges oder beschädigtes Gzip") }
            }
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        var nodes = 0
        mutating func byte() throws -> UInt8 {
            guard position < bytes.count else { throw FT2Error.invalid("unerwartetes Dateiende") }
            defer { position += 1 }; return bytes[position]
        }
        mutating func unsigned(_ count: Int) throws -> UInt64 {
            var value: UInt64 = 0
            for _ in 0..<count { value = (value << 8) | UInt64(try byte()) }
            return value
        }
        mutating func root() throws -> [Int64: Int64] {
            guard try byte() == 0xc1 else { throw FT2Error.invalid("Wurzelobjekt") }
            var values: [Int64: Int64] = [:]
            var keys = Set<Int64>()
            while try peek() != 0xc8 {
                guard let key = try value(depth: 1), keys.insert(key).inserted else {
                    throw FT2Error.invalid("Feldkennung oder doppeltes Feld")
                }
                let v = try value(depth: 1)
                if [0, 15, 16, 18, 21].contains(key) {
                    guard let v else { throw FT2Error.invalid("Feldtyp") }; values[key] = v
                }
            }
            _ = try byte()
            guard position == bytes.count, values[0] == 347 else {
                throw FT2Error.invalid("unbekannte Formatversion oder Restdaten")
            }
            return values
        }
        func peek() throws -> UInt8 {
            guard position < bytes.count else { throw FT2Error.invalid("fehlender Abschluss") }
            return bytes[position]
        }
        /// Returns integer scalars; validates and skips all other supported values.
        mutating func value(depth: Int) throws -> Int64? {
            nodes += 1
            guard depth <= 64, nodes <= 4_000_000 else { throw FT2Error.invalid("Strukturlimit") }
            let tag = try byte()
            if tag < 0x80 { return Int64(tag) }
            if tag >= 0xe0 { return Int64(Int8(bitPattern: tag)) }
            if (0xa0...0xbf).contains(tag) {
                let length = Int(tag & 31)
                guard position + length <= bytes.count,
                      String(bytes: bytes[position..<position + length], encoding: .utf8) != nil else {
                    throw FT2Error.invalid("Zeichenkette")
                }
                position += length; return nil
            }
            switch tag {
            case 0xc0, 0xc2, 0xc3: return nil
            case 0xcc: return Int64(try unsigned(1))
            case 0xcd: return Int64(try unsigned(2))
            case 0xce: return Int64(try unsigned(4))
            case 0xcf:
                let v = try unsigned(8)
                // UInt64 is supported when skipping; synchronization fields must fit Int64.
                return Int64(exactly: v)
            case 0xd0: return Int64(Int8(bitPattern: UInt8(try unsigned(1))))
            case 0xd1: return Int64(Int16(bitPattern: UInt16(try unsigned(2))))
            case 0xd2: return Int64(Int32(bitPattern: UInt32(try unsigned(4))))
            case 0xd3: return Int64(bitPattern: try unsigned(8))
            case 0xca: _ = try unsigned(4); return nil
            case 0xcb: _ = try unsigned(8); return nil
            case 0xc1, 0xc7:
                var keys = Set<Int64>()
                while try peek() != 0xc8 {
                    if tag == 0xc1 {
                        guard let key = try value(depth: depth + 1), keys.insert(key).inserted else {
                            throw FT2Error.invalid("Objektfeld")
                        }
                    }
                    _ = try value(depth: depth + 1)
                }
                _ = try byte(); return nil
            default: throw FT2Error.invalid(String(format: "unbekanntes Typbyte %02X", tag))
            }
        }
    }
}
