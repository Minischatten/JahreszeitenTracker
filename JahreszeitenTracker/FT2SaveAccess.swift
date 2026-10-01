import Foundation
import Darwin

nonisolated struct CatalogScanResult: Sendable {
    let readings: [FarmReading]?
    let message: String
    let refreshedBookmark: Data?
}

/// This boundary has no write operations. Descriptors are always O_RDONLY,
/// symlinks are refused, and decompression uses an in-memory copy only.
nonisolated enum FT2SaveAccess {
    static func scanCatalog(bookmark: Data, now: Date) -> CatalogScanResult {
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            guard folder.startAccessingSecurityScopedResource() else { throw FT2Error.invalid("Ordner erneut auswählen") }
            defer { folder.stopAccessingSecurityScopedResource() }
            let readings = try catalog(in: folder, now: now)
            let replacement = stale ? try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                               includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            return CatalogScanResult(readings: readings, message: "", refreshedBookmark: replacement)
        } catch {
            return CatalogScanResult(readings: nil, message: error.localizedDescription, refreshedBookmark: nil)
        }
    }

    static func catalog(in root: URL, now: Date) throws -> [FarmReading] {
        let metadataURL = root.appendingPathComponent("farms.mlk")
        let snapshot = try readOnlySnapshot(metadataURL)
        let metadata = try FT2MetadataParser.parse(snapshot, now: now)
        let areas = root.appendingPathComponent("farms", isDirectory: true)
        // Refuse a redirected area directory as well as final-file symlinks.
        let attributes = try? areas.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let safeDirectory = attributes?.isSymbolicLink == false && attributes?.isDirectory == true
        let readings = metadata.map { farm -> FarmReading in
            do {
                guard safeDirectory else { throw FT2Error.invalid("Bereichsordner fehlt oder ist verknüpft") }
                let reference = try newest(in: areas, slot: farm.slotIndex, now: now, createdAt: farm.creationTime)
                return FarmReading(metadata: farm, reference: reference,
                                   message: reference == nil ? "Kein gültiger Bereichsspielstand" : "")
            } catch { return FarmReading(metadata: farm, reference: nil, message: error.localizedDescription) }
        }
        guard try readOnlySnapshot(metadataURL) == snapshot else { throw FT2Error.invalid("Metadaten während Scan verändert") }
        return readings
    }
    /// Searches only the selected directory, only exact area-save filenames.
    /// No recursive traversal, .bak files, global saves, or modification-date ordering.
    static func newest(in folder: URL, slot: Int, now: Date, createdAt: Int64? = nil) throws -> SaveReference? {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let allowed = Set((0..<6).map { "farm_\(slot)_\($0).data" })
        var newest: SaveReference?
        var conflict = false
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where allowed.contains(file.lastPathComponent) {
            guard let bytes = try? readOnlySnapshot(file),
                  let reference = try? FT2SaveParser.parse(bytes, sourceName: file.lastPathComponent, now: now),
                  createdAt.map({ reference.savedTicks >= $0 }) ?? true else { continue }
            if newest == nil || reference.savedTicks > newest!.savedTicks {
                newest = reference; conflict = false
            } else if reference.savedTicks == newest!.savedTicks {
                let previous = newest!
                if reference.gameTime != previous.gameTime || reference.nextBoundary != previous.nextBoundary || reference.seasonIndex != previous.seasonIndex {
                    conflict = true
                }
            }
        }
        guard !conflict else { throw FT2Error.invalid("widersprüchliche Bereichsdateien mit gleichem Zeitstempel") }
        return newest
    }

    static func readOnlySnapshot(_ url: URL) throws -> Data {
        let fd = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) } ?? -1
        }
        guard fd >= 0 else { throw FT2Error.invalid("Datei nicht lesbar") }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size > 0, before.st_size <= FT2SaveParser.maximumCompressedSize else {
            throw FT2Error.invalid("Dateityp oder Größe")
        }
        var bytes = [UInt8](repeating: 0, count: Int(before.st_size))
        var offset = 0
        try bytes.withUnsafeMutableBytes { buffer in
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw FT2Error.invalid("Datei während Lesen unvollständig") }
                offset += count
            }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw FT2Error.invalid("Datei während Lesen verändert")
        }
        return Data(bytes)
    }
}
