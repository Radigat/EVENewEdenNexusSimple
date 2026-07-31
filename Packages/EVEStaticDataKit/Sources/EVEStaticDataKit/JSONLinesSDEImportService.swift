import CryptoKit
import CoreFoundation
import Foundation

public actor JSONLinesSDEImportService: SDEImporting {
    public static let formatIdentifier = "com.evestaticdatakit.sde-staging"
    public static let formatVersion = 1
    public static let packageExtension = "evesde"
    public static let manifestFileName = "manifest.json"
    public static let licenseURL = "https://developers.eveonline.com/license-agreement"

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let readChunkSize: Int
    private let maximumLineBytes: Int

    public init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init,
        readChunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.now = now
        self.makeID = makeID
        self.readChunkSize = max(1_024, readChunkSize)
        self.maximumLineBytes = max(1_024, maximumLineBytes)
    }

    public func preview(
        sourceDirectoryURL: URL,
        buildNumber: Int,
        progress: SDEImportProgressHandler?
    ) async throws -> SDEImportPreview {
        try Task.checkCancellation()
        guard buildNumber > 0 else {
            throw SDEImportError.invalidBuildNumber
        }
        try validateDirectory(sourceDirectoryURL, missingIsSource: true)
        let snapshot = try inspect(
            directoryURL: sourceDirectoryURL,
            buildNumber: buildNumber,
            phase: .inspecting,
            progress: progress
        )
        return SDEImportPreview(
            sourceDirectoryURL: sourceDirectoryURL,
            snapshot: snapshot
        )
    }

    public func stageImport(
        preview: SDEImportPreview,
        destinationDirectoryURL: URL,
        progress: SDEImportProgressHandler?
    ) async throws -> SDEStagingPackageDescriptor {
        try Task.checkCancellation()
        try validateDirectory(preview.sourceDirectoryURL, missingIsSource: true)
        try prepareDestinationDirectory(destinationDirectoryURL)

        let packageID = makeID()
        let stagingURL = destinationDirectoryURL.appendingPathComponent(
            ".EVEStaticDataKit-SDE-\(packageID.uuidString).partial",
            isDirectory: true
        )
        let packageURL = destinationDirectoryURL
            .appendingPathComponent(
                "EVEStaticDataKit-SDE-\(preview.snapshot.buildNumber)-\(packageID.uuidString)",
                isDirectory: true
            )
            .appendingPathExtension(Self.packageExtension)

        guard !fileManager.fileExists(atPath: stagingURL.path),
              !fileManager.fileExists(atPath: packageURL.path) else {
            throw SDEImportError.packageAlreadyExists
        }

        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            for (index, kind) in SDEDatasetKind.allCases.enumerated() {
                try Task.checkCancellation()
                progress?(
                    SDEImportProgress(
                        phase: .copying,
                        dataset: kind,
                        completedDatasets: index,
                        totalDatasets: SDEDatasetKind.allCases.count,
                        recordsProcessed: 0
                    )
                )
                let sourceURL = preview.sourceDirectoryURL
                    .appendingPathComponent(kind.fileName)
                try validateDatasetFile(sourceURL, kind: kind)
                let destinationURL = stagingURL
                    .appendingPathComponent(kind.fileName)
                do {
                    try fileManager.copyItem(
                        at: sourceURL,
                        to: destinationURL
                    )
                    try setPrivateFilePermissions(at: destinationURL)
                } catch let error as SDEImportError {
                    throw error
                } catch {
                    throw SDEImportError.fileOperationFailed(.copyDataset)
                }
            }

            let stagedSnapshot = try inspect(
                directoryURL: stagingURL,
                buildNumber: preview.snapshot.buildNumber,
                phase: .verifying,
                progress: progress
            )
            guard stagedSnapshot == preview.snapshot else {
                throw SDEImportError.sourceChangedSincePreview
            }

            let createdAt = Date(
                timeIntervalSince1970: floor(now().timeIntervalSince1970)
            )
            let manifest = SDEStagingManifest(
                formatIdentifier: Self.formatIdentifier,
                formatVersion: Self.formatVersion,
                packageID: packageID,
                createdAt: createdAt,
                snapshot: stagedSnapshot
            )
            try writeManifest(manifest, to: stagingURL)
            progress?(
                SDEImportProgress(
                    phase: .publishing,
                    dataset: nil,
                    completedDatasets: SDEDatasetKind.allCases.count,
                    totalDatasets: SDEDatasetKind.allCases.count,
                    recordsProcessed: stagedSnapshot.datasets
                        .reduce(0) { $0 + $1.recordCount }
                )
            )
            do {
                try fileManager.moveItem(at: stagingURL, to: packageURL)
            } catch {
                throw SDEImportError.fileOperationFailed(.publishPackage)
            }
            progress?(
                SDEImportProgress(
                    phase: .completed,
                    dataset: nil,
                    completedDatasets: SDEDatasetKind.allCases.count,
                    totalDatasets: SDEDatasetKind.allCases.count,
                    recordsProcessed: stagedSnapshot.datasets
                        .reduce(0) { $0 + $1.recordCount }
                )
            )
            return SDEStagingPackageDescriptor(
                packageURL: packageURL,
                manifest: manifest
            )
        } catch {
            do {
                try removeIfPresent(stagingURL)
            } catch {
                throw SDEImportError.fileOperationFailed(.cleanup)
            }
            if error is CancellationError {
                throw error
            }
            if let importError = error as? SDEImportError {
                throw importError
            }
            throw SDEImportError.fileOperationFailed(.createStaging)
        }
    }

    private func inspect(
        directoryURL: URL,
        buildNumber: Int,
        phase: SDEImportProgressPhase,
        progress: SDEImportProgressHandler?
    ) throws -> SDEImportSnapshot {
        var descriptors: [SDEDatasetDescriptor] = []
        for (index, kind) in SDEDatasetKind.allCases.enumerated() {
            try Task.checkCancellation()
            let datasetURL = directoryURL.appendingPathComponent(kind.fileName)
            try validateDatasetFile(datasetURL, kind: kind)
            let descriptor = try inspectDataset(
                at: datasetURL,
                kind: kind,
                phase: phase,
                completedDatasets: index,
                progress: progress
            )
            descriptors.append(descriptor)
        }

        return SDEImportSnapshot(
            buildNumber: buildNumber,
            sourceFormat: .jsonLines,
            officialArchiveURL: officialArchiveURL(buildNumber: buildNumber),
            licenseURL: Self.licenseURL,
            datasets: descriptors,
            contentSHA256: SDEContentHash.make(
                buildNumber: buildNumber,
                descriptors: descriptors
            )
        )
    }

    private func inspectDataset(
        at url: URL,
        kind: SDEDatasetKind,
        phase: SDEImportProgressPhase,
        completedDatasets: Int,
        progress: SDEImportProgressHandler?
    ) throws -> SDEDatasetDescriptor {
        do {
            return try withReadableFileHandle(at: url) { handle in
                var hasher = SHA256()
                var byteCount: Int64 = 0
                var recordCount = 0
                var lineNumber = 0
                var buffer = Data()
                var knownKeys = Set<Int>()

                while let chunk = try handle.read(upToCount: readChunkSize),
                      !chunk.isEmpty {
                    try Task.checkCancellation()
                    hasher.update(data: chunk)
                    byteCount += Int64(chunk.count)
                    buffer.append(chunk)

                    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                        let line = Data(buffer[..<newlineIndex])
                        buffer.removeSubrange(...newlineIndex)
                        lineNumber += 1
                        try validateLine(
                            line,
                            kind: kind,
                            lineNumber: lineNumber,
                            knownKeys: &knownKeys
                        )
                        recordCount += 1
                        if recordCount.isMultiple(of: 10_000) {
                            reportProgress(
                                phase: phase,
                                kind: kind,
                                completedDatasets: completedDatasets,
                                recordsProcessed: recordCount,
                                progress: progress
                            )
                        }
                    }

                    if buffer.count > maximumLineBytes {
                        throw SDEImportError.lineTooLarge(
                            dataset: kind,
                            line: lineNumber + 1,
                            maximumBytes: maximumLineBytes
                        )
                    }
                }

                if !buffer.isEmpty {
                    lineNumber += 1
                    try validateLine(
                        buffer,
                        kind: kind,
                        lineNumber: lineNumber,
                        knownKeys: &knownKeys
                    )
                    recordCount += 1
                }
                guard recordCount > 0 else {
                    throw SDEImportError.emptyDataset(kind)
                }

                reportProgress(
                    phase: phase,
                    kind: kind,
                    completedDatasets: completedDatasets + 1,
                    recordsProcessed: recordCount,
                    progress: progress
                )
                return SDEDatasetDescriptor(
                    kind: kind,
                    fileName: kind.fileName,
                    recordCount: recordCount,
                    byteCount: byteCount,
                    sha256: hasher.finalize().hexString
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SDEImportError {
            throw error
        } catch {
            throw SDEImportError.fileOperationFailed(.readDataset)
        }
    }

    private func validateLine(
        _ rawLine: Data,
        kind: SDEDatasetKind,
        lineNumber: Int,
        knownKeys: inout Set<Int>
    ) throws {
        var line = rawLine
        if line.last == 0x0D {
            line.removeLast()
        }
        guard !line.isEmpty else {
            throw SDEImportError.emptyLine(
                dataset: kind,
                line: lineNumber
            )
        }
        guard line.count <= maximumLineBytes else {
            throw SDEImportError.lineTooLarge(
                dataset: kind,
                line: lineNumber,
                maximumBytes: maximumLineBytes
            )
        }
        guard String(data: line, encoding: .utf8) != nil else {
            throw SDEImportError.invalidUTF8(
                dataset: kind,
                line: lineNumber
            )
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: line)
        } catch {
            throw SDEImportError.invalidJSON(
                dataset: kind,
                line: lineNumber
            )
        }
        guard let object = value as? [String: Any] else {
            throw SDEImportError.invalidRootObject(
                dataset: kind,
                line: lineNumber
            )
        }
        guard let rawKey = object["_key"] else {
            throw SDEImportError.missingRecordKey(
                dataset: kind,
                line: lineNumber
            )
        }
        guard let number = rawKey as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let key = Int(exactly: number.int64Value),
              Decimal(key) == number.decimalValue,
              key >= 0 else {
            throw SDEImportError.invalidRecordKey(
                dataset: kind,
                line: lineNumber
            )
        }
        guard knownKeys.insert(key).inserted else {
            throw SDEImportError.duplicateRecordKey(
                dataset: kind,
                line: lineNumber,
                key: key
            )
        }
    }

    private func reportProgress(
        phase: SDEImportProgressPhase,
        kind: SDEDatasetKind,
        completedDatasets: Int,
        recordsProcessed: Int,
        progress: SDEImportProgressHandler?
    ) {
        progress?(
            SDEImportProgress(
                phase: phase,
                dataset: kind,
                completedDatasets: completedDatasets,
                totalDatasets: SDEDatasetKind.allCases.count,
                recordsProcessed: recordsProcessed
            )
        )
    }

    private func officialArchiveURL(buildNumber: Int) -> String {
        "https://developers.eveonline.com/static-data/tranquility/"
            + "eve-online-static-data-\(buildNumber)-jsonl.zip"
    }

    private func validateDirectory(
        _ url: URL,
        missingIsSource: Bool
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            if missingIsSource {
                throw SDEImportError.sourceDirectoryMissing
            }
            throw SDEImportError.fileOperationFailed(.createDestination)
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw SDEImportError.unsafeSymbolicLink(dataset: nil)
            }
            guard values.isDirectory == true else {
                if missingIsSource {
                    throw SDEImportError.sourceDirectoryMissing
                }
                throw SDEImportError.fileOperationFailed(.createDestination)
            }
        } catch let error as SDEImportError {
            throw error
        } catch {
            throw SDEImportError.fileOperationFailed(.validateSource)
        }
    }

    private func validateDatasetFile(
        _ url: URL,
        kind: SDEDatasetKind
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw SDEImportError.missingDataset(kind)
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw SDEImportError.unsafeSymbolicLink(dataset: kind)
            }
            guard values.isRegularFile == true else {
                throw SDEImportError.missingDataset(kind)
            }
        } catch let error as SDEImportError {
            throw error
        } catch {
            throw SDEImportError.fileOperationFailed(.validateSource)
        }
    }

    private func prepareDestinationDirectory(_ url: URL) throws {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try validateDirectory(url, missingIsSource: false)
            } else {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        } catch let error as SDEImportError {
            throw error
        } catch {
            throw SDEImportError.fileOperationFailed(.createDestination)
        }
    }

    private func writeManifest(
        _ manifest: SDEStagingManifest,
        to stagingURL: URL
    ) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = stagingURL
                .appendingPathComponent(Self.manifestFileName)
            try data.write(to: manifestURL, options: .atomic)
            try setPrivateFilePermissions(at: manifestURL)
        } catch let error as SDEImportError {
            throw error
        } catch {
            throw SDEImportError.fileOperationFailed(.writeManifest)
        }
    }

    private func setPrivateFilePermissions(at url: URL) throws {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw SDEImportError.fileOperationFailed(.setPermissions)
        }
    }

    private func withReadableFileHandle<Output>(
        at url: URL,
        _ body: (FileHandle) throws -> Output
    ) throws -> Output {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SDEImportError.fileOperationFailed(.openDataset)
        }

        let result: Swift.Result<Output, any Error>
        do {
            result = .success(try body(handle))
        } catch {
            result = .failure(error)
        }
        do {
            try handle.close()
        } catch {
            throw SDEImportError.fileOperationFailed(.closeDataset)
        }
        return try result.get()
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}
