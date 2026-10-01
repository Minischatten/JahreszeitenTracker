import Foundation

nonisolated struct FT2FarmMetadata: Decodable, Equatable, Sendable {
    let slotIndex: Int
    let creationTime: Int64
    let name: String

    private enum CodingKeys: String, CodingKey { case slotIndex, farm }
    private struct Header: Decodable {
        let name: String
        let creation_time: Int64
    }
    init(slotIndex: Int, creationTime: Int64, name: String) {
        self.slotIndex = slotIndex; self.creationTime = creationTime; self.name = name
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slotIndex = try container.decode(Int.self, forKey: .slotIndex)
        let header = try container.decode(Header.self, forKey: .farm)
        creationTime = header.creation_time; name = header.name
    }
}

/// SaveStream.ConvertFromByte -> Gzip -> UTF-8 JSON with unquoted property names.
/// No evaluation of text; quoted strings are copied without substitution.
nonisolated enum FT2MetadataParser {
    private struct Root: Decodable { let version: Int; let farms: [FT2FarmMetadata] }
    static func parse(_ input: Data, now: Date = Date()) throws -> [FT2FarmMetadata] {
        guard input.count <= FT2SaveParser.maximumCompressedSize else { throw FT2Error.invalid("Metadatengröße") }
        let decoded = Data(input.map { ($0 ^ 255) &+ 31 })
        var normalizer = Normalizer(bytes: Array(try FT2SaveParser.gunzip(decoded)))
        let document = try normalizer.document()
        let root = try JSONDecoder().decode(Root.self, from: document)
        guard root.version == 347, root.farms.count <= 10_000 else { throw FT2Error.invalid("Metadatenversion oder Farmanzahl") }
        var slots = Set<Int>()
        for farm in root.farms {
            guard farm.slotIndex >= 0, farm.slotIndex <= Int(Int32.max), slots.insert(farm.slotIndex).inserted,
                  farm.name.utf8.count <= 4096,
                  try TrackerClock.date(ticks: farm.creationTime) <= now.addingTimeInterval(300) else {
                throw FT2Error.invalid("Farmidentität oder doppelter Slot")
            }
        }
        return root.farms
    }

    private struct Normalizer {
        let bytes: [UInt8]
        var position = 0
        var nodes = 0
        var output: [UInt8] = []
        mutating func whitespace() { while position < bytes.count && [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
        mutating func expect(_ byte: UInt8) throws {
            whitespace()
            guard position < bytes.count, bytes[position] == byte else { throw FT2Error.invalid("Metadatenstruktur") }
            position += 1; output.append(byte)
        }
        mutating func string() throws -> String {
            let start = position
            guard position < bytes.count, bytes[position] == 34 else { throw FT2Error.invalid("Metadatenzeichenkette") }
            position += 1
            var escaped = false
            while position < bytes.count {
                let byte = bytes[position]; position += 1
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 {
                    let data = Data(bytes[start..<position])
                    let text = try JSONDecoder().decode(String.self, from: data)
                    output.append(contentsOf: data)
                    return text
                }
            }
            throw FT2Error.invalid("unvollständige Metadatenzeichenkette")
        }
        func identifier(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || (48...57).contains(byte)
        }
        mutating func value(depth: Int) throws {
            nodes += 1; whitespace()
            guard depth <= 64, nodes <= 4_000_000, position < bytes.count else { throw FT2Error.invalid("Metadatenlimit oder Dateiende") }
            switch bytes[position] {
            case 123:
                try expect(123); whitespace(); var keys = Set<String>()
                if position < bytes.count, bytes[position] != 125 {
                    while true {
                        whitespace()
                        let key: String
                        if position < bytes.count, bytes[position] == 34 { key = try string() }
                        else {
                            let start = position
                            while position < bytes.count && identifier(bytes[position]) { position += 1 }
                            guard position > start, !(48...57).contains(bytes[start]) else { throw FT2Error.invalid("Metadatenschlüssel") }
                            key = String(decoding: bytes[start..<position], as: UTF8.self)
                            output.append(34); output.append(contentsOf: key.utf8); output.append(34)
                        }
                        guard keys.insert(key).inserted else { throw FT2Error.invalid("doppelter Metadatenschlüssel") }
                        try expect(58); try value(depth: depth + 1); whitespace()
                        if position < bytes.count, bytes[position] == 44 { try expect(44) } else { break }
                    }
                }
                try expect(125)
            case 91:
                try expect(91); whitespace()
                if position < bytes.count, bytes[position] != 93 {
                    while true {
                        try value(depth: depth + 1); whitespace()
                        if position < bytes.count, bytes[position] == 44 { try expect(44) } else { break }
                    }
                }
                try expect(93)
            case 34: _ = try string()
            default:
                let start = position
                while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) { position += 1 }
                guard position > start else { throw FT2Error.invalid("Metadatenwert") }
                output.append(contentsOf: bytes[start..<position])
            }
        }
        mutating func document() throws -> Data {
            if bytes.starts(with: [0xef, 0xbb, 0xbf]) { position = 3 }
            try value(depth: 0); whitespace()
            guard position == bytes.count else { throw FT2Error.invalid("Metadatenrest") }
            // JSONDecoder validates literals/numbers after property-name normalization.
            return Data(output)
        }
    }
}
