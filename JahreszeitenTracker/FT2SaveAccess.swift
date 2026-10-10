import Foundation
import Darwin

nonisolated struct CatalogScanResult: Sendable {
    let readings: [FarmReading]?
    let message: String
    var refreshedBookmark: Data?
    var metadataVersion: Int? = nil
    var metadataRejected = false
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
            var result = try catalogSnapshot(in: folder, now: now)
            let replacement = stale ? try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                               includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            result.refreshedBookmark = replacement
            return result
        } catch {
            return failedScan(error)
        }
    }

    static func failedScan(_ error: Error) -> CatalogScanResult {
        var result = CatalogScanResult(readings: nil, message: error.localizedDescription, refreshedBookmark: nil)
        result.metadataVersion = (error as? FT2VersionError)?.version
        result.metadataRejected = result.metadataVersion.map { $0 > 347 } ?? false
        return result
    }

    static func catalog(in root: URL, now: Date) throws -> [FarmReading] {
        try catalogSnapshot(in: root, now: now).readings ?? []
    }

    static func catalogSnapshot(in root: URL, now: Date) throws -> CatalogScanResult {
        let metadataURL = root.appendingPathComponent("farms.mlk")
        let snapshot = try readOnlySnapshot(metadataURL)
        let document = try FT2MetadataParser.parseDocument(snapshot, now: now)
        let metadata = document.farms
        let areas = root.appendingPathComponent("farms", isDirectory: true)
        // Refuse a redirected area directory as well as final-file symlinks.
        let attributes = try? areas.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let safeDirectory = attributes?.isSymbolicLink == false && attributes?.isDirectory == true
        let readings = metadata.map { farm -> FarmReading in
            do {
                guard safeDirectory else { throw FT2Error.invalid("Bereichsordner fehlt oder ist verknüpft") }
                let observation = try areaSnapshot(in: areas, slot: farm.slotIndex, now: now, createdAt: farm.creationTime)
                return FarmReading(metadata: farm, reference: observation.reference,
                                   message: observation.reference == nil ? "Kein gültiger Bereichsspielstand" : "",
                                   rejectedVersions: observation.rejectedVersions,
                                   observedPlotVersion: observation.observedVersion)
            } catch { return FarmReading(metadata: farm, reference: nil, message: error.localizedDescription) }
        }
        guard try readOnlySnapshot(metadataURL) == snapshot else { throw FT2Error.invalid("Metadaten während Scan verändert") }
        return CatalogScanResult(readings: readings, message: "", refreshedBookmark: nil, metadataVersion: document.version)
    }
    /// Searches only the selected directory, only exact area-save filenames.
    /// No recursive traversal, .bak files, global saves, or modification-date ordering.
    static func newest(in folder: URL, slot: Int, now: Date, createdAt: Int64? = nil) throws -> SaveReference? {
        let result = try areaSnapshot(in: folder, slot: slot, now: now, createdAt: createdAt)
        guard !result.conflict else { throw FT2Error.invalid("widersprüchliche Bereichsdateien mit gleichem Zeitstempel") }
        return result.reference
    }

    struct AreaObservation {
        var reference: SaveReference?
        var rejectedVersions: [Int] = []
        var observedVersion: Int?
        var conflict = false
    }
    static func areaSnapshot(in folder: URL, slot: Int, now: Date, createdAt: Int64? = nil) throws -> AreaObservation {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var newest: SaveReference?
        var conflict = false
        var rejectedVersions = Set<Int>()
        var newestVersions = Set<Int>()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where isAreaFilename(file.lastPathComponent, slot: slot) {
            guard let bytes = try? readOnlySnapshot(file) else { continue }
            let reference: SaveReference
            do {
                reference = try FT2SaveParser.parse(bytes, sourceName: file.lastPathComponent, now: now)
            } catch {
                // A malformed file cannot prove its age or ownership. Retain a
                // conservative warning when a newer format was actually read.
                if let version = (error as? FT2VersionError)?.version, version > 347 {
                    rejectedVersions.insert(version)
                }
                continue
            }
            guard createdAt.map({ reference.savedTicks >= $0 }) ?? true else { continue }
            if newest == nil || reference.savedTicks > newest!.savedTicks {
                newest = reference; conflict = false; newestVersions = [reference.version]
            } else if reference.savedTicks == newest!.savedTicks {
                newestVersions.insert(reference.version)
                let previous = newest!
                if reference.gameTime != previous.gameTime || reference.nextBoundary != previous.nextBoundary || reference.seasonIndex != previous.seasonIndex {
                    conflict = true
                } else if reference.version > previous.version {
                    newest = reference
                }
            }
        }
        if conflict { rejectedVersions.formUnion(newestVersions.filter { $0 > 347 }) }
        return AreaObservation(reference: conflict ? nil : newest,
                               rejectedVersions: rejectedVersions.sorted(),
                               observedVersion: newestVersions.max(), conflict: conflict)
    }

    static func isAreaFilename(_ name: String, slot: Int) -> Bool {
        let prefix = "farm_\(slot)_"
        guard slot >= 0, name.hasPrefix(prefix), name.hasSuffix(".data") else { return false }
        let indexText = name.dropFirst(prefix.count).dropLast(5)
        guard !indexText.isEmpty, indexText.utf8.allSatisfy({ (48...57).contains($0) }),
              let index = Int(indexText), index >= 0 else { return false }
        return name == "\(prefix)\(index).data"
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
