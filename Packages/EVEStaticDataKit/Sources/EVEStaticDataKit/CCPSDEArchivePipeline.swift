import Foundation

public struct SDEArchiveSafetyLimits: Equatable, Sendable {
    public let maximumEntryCount: Int
    public let maximumEntryBytes: Int64
    public let maximumExpandedBytes: Int64
    public let maximumCompressionRatio: Double
    public let minimumFreeSpaceReserveBytes: Int64

    public init(
        maximumEntryCount: Int = 20_000,
        maximumEntryBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
        maximumExpandedBytes: Int64 = 20 * 1_024 * 1_024 * 1_024,
        maximumCompressionRatio: Double = 250,
        minimumFreeSpaceReserveBytes: Int64 = 512 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumEntryBytes = maximumEntryBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumCompressionRatio = maximumCompressionRatio
        self.minimumFreeSpaceReserveBytes = minimumFreeSpaceReserveBytes
    }
}
public protocol SDEArchiveCommandRunning: Sendable {
    func extractZIP(archiveURL: URL, destinationURL: URL) async throws
}

public final class DittoSDEArchiveCommandRunner:
    SDEArchiveCommandRunning,
    @unchecked Sendable {
    public init() {}

    public func extractZIP(
        archiveURL: URL,
        destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-x", "-k", archiveURL.path, destinationURL.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationReason == .exit,
                  process.terminationStatus == 0 else {
                throw SDEInstallationError.extractionFailed
            }
        }.value
    }
}

public actor SecureSDEArchivePreparer: SDEArchivePreparing {
    private struct Entry {
        let path: String
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: UInt32
        let isDirectory: Bool
    }

    private let commandRunner: any SDEArchiveCommandRunning
    private let capacityReader: any SDEAvailableCapacityReading
    private let limits: SDEArchiveSafetyLimits
    private let fileManager: FileManager

    public init(
        commandRunner: any SDEArchiveCommandRunning =
            DittoSDEArchiveCommandRunner(),
        capacityReader: any SDEAvailableCapacityReading =
            VolumeSDEAvailableCapacityReader(),
        limits: SDEArchiveSafetyLimits = SDEArchiveSafetyLimits(),
        fileManager: FileManager = .default
    ) {
        self.commandRunner = commandRunner
        self.capacityReader = capacityReader
        self.limits = limits
        self.fileManager = fileManager
    }

    public func prepare(
        _ download: SDEArchiveDownload
    ) async throws -> SDEPreparedArchive {
        let entries = try inspectEntries(at: download.archiveURL)
        let inspection = try makeInspection(entries)
        let operationDirectory = download.archiveURL.deletingLastPathComponent()
        let requiredCapacity = inspection.uncompressedByteCount
            + limits.minimumFreeSpaceReserveBytes
        guard try capacityReader.availableCapacity(at: operationDirectory)
                >= requiredCapacity else {
            throw SDEInstallationError.insufficientDiskSpace
        }
        let destination = operationDirectory.appendingPathComponent(
            "extracted",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw SDEInstallationError.extractionFailed
        }
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            try await commandRunner.extractZIP(
                archiveURL: download.archiveURL,
                destinationURL: destination
            )
            try validateExtractedDirectory(
                destination,
                expected: entries,
                inspection: inspection
            )
            return SDEPreparedArchive(
                extractedDirectoryURL: destination,
                inspection: inspection
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func cleanup(operationID: UUID) async throws {
        // The downloader owns and removes the common operation directory.
    }

    private func inspectEntries(at archiveURL: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else {
            throw SDEInstallationError.damagedArchive
        }
        let tailSize = min(fileSize, UInt64(65_557))
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
        guard let eocdOffset = tail.lastIndex(ofLittleEndian: 0x06054b50),
              eocdOffset + 22 <= tail.count else {
            throw SDEInstallationError.damagedArchive
        }
        let disk = tail.uint16LE(at: eocdOffset + 4)
        let centralDisk = tail.uint16LE(at: eocdOffset + 6)
        let entriesOnDisk = tail.uint16LE(at: eocdOffset + 8)
        let entryCount = tail.uint16LE(at: eocdOffset + 10)
        let centralSize = tail.uint32LE(at: eocdOffset + 12)
        let centralOffset = tail.uint32LE(at: eocdOffset + 16)
        guard disk == 0, centralDisk == 0,
              entriesOnDisk == entryCount else {
            throw SDEInstallationError.multipartArchive
        }
        guard entryCount != UInt16.max,
              centralSize != UInt32.max,
              centralOffset != UInt32.max else {
            throw SDEInstallationError.unsafeArchive
        }
        guard Int(entryCount) <= limits.maximumEntryCount else {
            throw SDEInstallationError.tooManyArchiveEntries
        }
        guard UInt64(centralOffset) + UInt64(centralSize) <= fileSize,
              centralSize <= 64 * 1_024 * 1_024 else {
            throw SDEInstallationError.damagedArchive
        }

        try handle.seek(toOffset: UInt64(centralOffset))
        let central = try handle.read(upToCount: Int(centralSize)) ?? Data()
        var cursor = 0
        var entries: [Entry] = []
        var normalizedPaths = Set<String>()
        for _ in 0..<entryCount {
            guard cursor + 46 <= central.count,
                  central.uint32LE(at: cursor) == 0x02014b50 else {
                throw SDEInstallationError.damagedArchive
            }
            let madeBy = central.uint16LE(at: cursor + 4)
            let flags = central.uint16LE(at: cursor + 8)
            let method = central.uint16LE(at: cursor + 10)
            let compressed = central.uint32LE(at: cursor + 20)
            let uncompressed = central.uint32LE(at: cursor + 24)
            let nameLength = Int(central.uint16LE(at: cursor + 28))
            let extraLength = Int(central.uint16LE(at: cursor + 30))
            let commentLength = Int(central.uint16LE(at: cursor + 32))
            let startDisk = central.uint16LE(at: cursor + 34)
            let externalAttributes = central.uint32LE(at: cursor + 38)
            let localOffset = central.uint32LE(at: cursor + 42)
            let end = cursor + 46 + nameLength + extraLength + commentLength
            guard end <= central.count, nameLength > 0 else {
                throw SDEInstallationError.damagedArchive
            }
            guard flags & 0x1 == 0 else {
                throw SDEInstallationError.encryptedArchive
            }
            guard startDisk == 0 else {
                throw SDEInstallationError.multipartArchive
            }
            guard method == 0 || method == 8 else {
                throw SDEInstallationError.unsafeArchive
            }
            guard compressed != UInt32.max,
                  uncompressed != UInt32.max else {
                throw SDEInstallationError.unsafeArchive
            }
            let nameData = central.subdata(
                in: (cursor + 46)..<(cursor + 46 + nameLength)
            )
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw SDEInstallationError.unsafeArchivePath
            }
            let isDirectory = name.hasSuffix("/")
            try validatePath(name, isDirectory: isDirectory)
            let normalized = name.precomposedStringWithCanonicalMapping
                .lowercased()
            guard normalizedPaths.insert(normalized).inserted else {
                throw SDEInstallationError.duplicateArchivePath
            }
            try validateObjectType(
                madeBy: madeBy,
                externalAttributes: externalAttributes,
                isDirectory: isDirectory
            )
            let compressed64 = Int64(compressed)
            let uncompressed64 = Int64(uncompressed)
            guard uncompressed64 <= limits.maximumEntryBytes else {
                throw SDEInstallationError.archiveEntryTooLarge
            }
            if uncompressed64 > 0 {
                guard compressed64 > 0,
                      Double(uncompressed64) / Double(compressed64)
                        <= limits.maximumCompressionRatio else {
                    throw SDEInstallationError
                        .archiveCompressionRatioTooHigh
                }
            }
            try validateLocalHeader(
                handle: handle,
                offset: localOffset,
                expectedNameData: nameData,
                expectedFlags: flags,
                expectedMethod: method,
                expectedCompressedSize: compressed,
                expectedUncompressedSize: uncompressed
            )
            entries.append(
                Entry(
                    path: name,
                    compressedSize: compressed64,
                    uncompressedSize: uncompressed64,
                    localHeaderOffset: localOffset,
                    isDirectory: isDirectory
                )
            )
            cursor = end
        }
        guard cursor == central.count else {
            throw SDEInstallationError.damagedArchive
        }
        return entries
    }

    private func makeInspection(
        _ entries: [Entry]
    ) throws -> SDEArchiveInspection {
        let files = entries.filter { !$0.isDirectory }
        let totalExpanded = try files.reduce(Int64(0)) { total, entry in
            let (value, overflow) = total.addingReportingOverflow(
                entry.uncompressedSize
            )
            guard !overflow, value <= limits.maximumExpandedBytes else {
                throw SDEInstallationError.archiveExpandedSizeTooLarge
            }
            return value
        }
        let required = Set(SDEDatasetKind.allCases.map(\.fileName))
        let available = Set(files.map(\.path))
        for dataset in SDEDatasetKind.allCases
        where !available.contains(dataset.fileName) {
            throw SDEInstallationError.missingRequiredDataset(dataset)
        }
        return SDEArchiveInspection(
            entryCount: entries.count,
            compressedByteCount: files.reduce(0) {
                $0 + $1.compressedSize
            },
            uncompressedByteCount: totalExpanded,
            requiredDatasetFileNames: required
        )
    }

    private func validatePath(
        _ path: String,
        isDirectory: Bool
    ) throws {
        guard path == path.precomposedStringWithCanonicalMapping,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains("\0"),
              path.range(
                of: #"^[A-Za-z]:"#,
                options: .regularExpression
              ) == nil else {
            throw SDEInstallationError.unsafeArchivePath
        }
        let trimmed = isDirectory ? String(path.dropLast()) : path
        let components = trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw SDEInstallationError.unsafeArchivePath
        }
        guard !isDirectory,
              components.count == 1,
              path.hasSuffix(".jsonl") else {
            throw SDEInstallationError.unexpectedArchiveEntry
        }
    }

    private func validateObjectType(
        madeBy: UInt16,
        externalAttributes: UInt32,
        isDirectory: Bool
    ) throws {
        let hostOS = UInt8(madeBy >> 8)
        guard hostOS == 3 else {
            return
        }
        let mode = (externalAttributes >> 16) & 0o170000
        if mode == 0 {
            return
        }
        let expected: UInt32 = isDirectory ? 0o040000 : 0o100000
        guard mode == expected else {
            throw SDEInstallationError.unsafeArchiveObject
        }
    }

    private func validateLocalHeader(
        handle: FileHandle,
        offset: UInt32,
        expectedNameData: Data,
        expectedFlags: UInt16,
        expectedMethod: UInt16,
        expectedCompressedSize: UInt32,
        expectedUncompressedSize: UInt32
    ) throws {
        try handle.seek(toOffset: UInt64(offset))
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30,
              header.uint32LE(at: 0) == 0x04034b50,
              header.uint16LE(at: 6) == expectedFlags,
              header.uint16LE(at: 8) == expectedMethod else {
            throw SDEInstallationError.damagedArchive
        }
        if expectedFlags & 0x8 == 0 {
            guard header.uint32LE(at: 18) == expectedCompressedSize,
                  header.uint32LE(at: 22) == expectedUncompressedSize else {
                throw SDEInstallationError.damagedArchive
            }
        }
        let nameLength = Int(header.uint16LE(at: 26))
        let localName = try handle.read(upToCount: nameLength) ?? Data()
        guard localName == expectedNameData else {
            throw SDEInstallationError.unsafeArchivePath
        }
    }

    private func validateExtractedDirectory(
        _ directory: URL,
        expected entries: [Entry],
        inspection: SDEArchiveInspection
    ) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard root == directory.standardizedFileURL else {
            throw SDEInstallationError.extractionValidationFailed
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: []
        ) else {
            throw SDEInstallationError.extractionValidationFailed
        }
        var paths = Set<String>()
        var byteCount: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey
                ]
            )
            guard values.isSymbolicLink != true else {
                throw SDEInstallationError.unsafeArchiveObject
            }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else {
                throw SDEInstallationError.unsafeArchivePath
            }
            if values.isDirectory == true {
                continue
            }
            let parent = url.deletingLastPathComponent().standardizedFileURL
            let relative = url.lastPathComponent
            guard values.isRegularFile == true,
                  relative.hasSuffix(".jsonl"),
                  parent == directory.standardizedFileURL else {
                throw SDEInstallationError.unexpectedArchiveEntry
            }
            paths.insert(relative)
            byteCount += Int64(values.fileSize ?? 0)
        }
        let expectedFiles = Set(
            entries.filter { !$0.isDirectory }.map(\.path)
        )
        guard paths == expectedFiles,
              byteCount == inspection.uncompressedByteCount else {
            throw SDEInstallationError.extractionValidationFailed
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func lastIndex(ofLittleEndian value: UInt32) -> Int? {
        guard count >= 4 else {
            return nil
        }
        for index in stride(from: count - 4, through: 0, by: -1)
        where uint32LE(at: index) == value {
            return index
        }
        return nil
    }
}
