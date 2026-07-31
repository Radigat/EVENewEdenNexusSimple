import Foundation

public enum SDEDatasetKind: String, CaseIterable, Codable, Equatable, Sendable {
    case categories
    case groups
    case types
    case blueprints
    case typeDogma
    case dogmaAttributes
    case dogmaEffects

    public var fileName: String {
        "\(rawValue).jsonl"
    }
}

public enum SDEImportSourceFormat: String, Codable, Equatable, Sendable {
    case jsonLines = "jsonl"
}

public struct SDEDatasetDescriptor: Codable, Equatable, Sendable {
    public let kind: SDEDatasetKind
    public let fileName: String
    public let recordCount: Int
    public let byteCount: Int64
    public let sha256: String

    public init(
        kind: SDEDatasetKind,
        fileName: String,
        recordCount: Int,
        byteCount: Int64,
        sha256: String
    ) {
        self.kind = kind
        self.fileName = fileName
        self.recordCount = recordCount
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct SDEImportSnapshot: Codable, Equatable, Sendable {
    public let buildNumber: Int
    public let sourceFormat: SDEImportSourceFormat
    public let officialArchiveURL: String
    public let licenseURL: String
    public let datasets: [SDEDatasetDescriptor]
    public let contentSHA256: String

    public init(
        buildNumber: Int,
        sourceFormat: SDEImportSourceFormat,
        officialArchiveURL: String,
        licenseURL: String,
        datasets: [SDEDatasetDescriptor],
        contentSHA256: String
    ) {
        self.buildNumber = buildNumber
        self.sourceFormat = sourceFormat
        self.officialArchiveURL = officialArchiveURL
        self.licenseURL = licenseURL
        self.datasets = datasets
        self.contentSHA256 = contentSHA256
    }
}

public struct SDEImportPreview: Equatable, Sendable {
    public let sourceDirectoryURL: URL
    public let snapshot: SDEImportSnapshot

    public init(
        sourceDirectoryURL: URL,
        snapshot: SDEImportSnapshot
    ) {
        self.sourceDirectoryURL = sourceDirectoryURL
        self.snapshot = snapshot
    }
}

public struct SDEStagingManifest: Codable, Equatable, Sendable {
    public let formatIdentifier: String
    public let formatVersion: Int
    public let packageID: UUID
    public let createdAt: Date
    public let snapshot: SDEImportSnapshot

    public init(
        formatIdentifier: String,
        formatVersion: Int,
        packageID: UUID,
        createdAt: Date,
        snapshot: SDEImportSnapshot
    ) {
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.packageID = packageID
        self.createdAt = createdAt
        self.snapshot = snapshot
    }
}

public struct SDEStagingPackageDescriptor: Equatable, Sendable {
    public let packageURL: URL
    public let manifest: SDEStagingManifest

    public init(
        packageURL: URL,
        manifest: SDEStagingManifest
    ) {
        self.packageURL = packageURL
        self.manifest = manifest
    }
}

public enum SDEImportProgressPhase: String, Equatable, Sendable {
    case inspecting
    case copying
    case verifying
    case publishing
    case completed
}

public struct SDEImportProgress: Equatable, Sendable {
    public let phase: SDEImportProgressPhase
    public let dataset: SDEDatasetKind?
    public let completedDatasets: Int
    public let totalDatasets: Int
    public let recordsProcessed: Int

    public init(
        phase: SDEImportProgressPhase,
        dataset: SDEDatasetKind?,
        completedDatasets: Int,
        totalDatasets: Int,
        recordsProcessed: Int
    ) {
        self.phase = phase
        self.dataset = dataset
        self.completedDatasets = completedDatasets
        self.totalDatasets = totalDatasets
        self.recordsProcessed = recordsProcessed
    }
}

public typealias SDEImportProgressHandler = @Sendable (SDEImportProgress) -> Void

public protocol SDEImporting: Sendable {
    func preview(
        sourceDirectoryURL: URL,
        buildNumber: Int,
        progress: SDEImportProgressHandler?
    ) async throws -> SDEImportPreview

    func stageImport(
        preview: SDEImportPreview,
        destinationDirectoryURL: URL,
        progress: SDEImportProgressHandler?
    ) async throws -> SDEStagingPackageDescriptor
}

public extension SDEImporting {
    func preview(
        sourceDirectoryURL: URL,
        buildNumber: Int
    ) async throws -> SDEImportPreview {
        try await preview(
            sourceDirectoryURL: sourceDirectoryURL,
            buildNumber: buildNumber,
            progress: nil
        )
    }

    func stageImport(
        preview: SDEImportPreview,
        destinationDirectoryURL: URL
    ) async throws -> SDEStagingPackageDescriptor {
        try await stageImport(
            preview: preview,
            destinationDirectoryURL: destinationDirectoryURL,
            progress: nil
        )
    }
}

public enum SDEImportFileOperation: String, Equatable, Sendable {
    case validateSource
    case openDataset
    case readDataset
    case closeDataset
    case createDestination
    case createStaging
    case copyDataset
    case setPermissions
    case writeManifest
    case publishPackage
    case cleanup
}

public enum SDEImportError: Error, Equatable, Sendable {
    case invalidBuildNumber
    case sourceDirectoryMissing
    case unsafeSymbolicLink(dataset: SDEDatasetKind?)
    case missingDataset(SDEDatasetKind)
    case emptyDataset(SDEDatasetKind)
    case emptyLine(dataset: SDEDatasetKind, line: Int)
    case invalidUTF8(dataset: SDEDatasetKind, line: Int)
    case lineTooLarge(dataset: SDEDatasetKind, line: Int, maximumBytes: Int)
    case invalidJSON(dataset: SDEDatasetKind, line: Int)
    case invalidRootObject(dataset: SDEDatasetKind, line: Int)
    case missingRecordKey(dataset: SDEDatasetKind, line: Int)
    case invalidRecordKey(dataset: SDEDatasetKind, line: Int)
    case duplicateRecordKey(dataset: SDEDatasetKind, line: Int, key: Int)
    case sourceChangedSincePreview
    case packageAlreadyExists
    case fileOperationFailed(SDEImportFileOperation)
}
