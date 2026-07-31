import Foundation

public enum SDEInstallationPhase: String, Codable, Equatable, Sendable {
    case started
    case downloading
    case inspectingArchive
    case extractingArchive
    case validatingSource
    case stagingPackage
    case mappingCatalog
    case validatingStagingStore
    case creatingSafetyBackup
    case promoting
    case completed
    case failed
    case cancelled
    case recovered
}

public enum SDEArchiveCacheDecision: String, Codable, Equatable, Sendable {
    case downloaded
    case revalidated
}

public struct SDEArchiveDownloadRequest: Equatable, Sendable {
    public let operationID: UUID
    public let buildNumber: Int
    public let validators: SDEHTTPValidators

    public init(
        operationID: UUID,
        buildNumber: Int,
        validators: SDEHTTPValidators = SDEHTTPValidators()
    ) {
        self.operationID = operationID
        self.buildNumber = buildNumber
        self.validators = validators
    }
}

public struct SDEArchiveDownload: Equatable, Sendable {
    public let operationID: UUID
    public let buildNumber: Int
    public let officialURL: URL
    public let archiveURL: URL
    public let byteCount: Int64
    public let httpStatus: Int
    public let validators: SDEHTTPValidators
    public let cacheDecision: SDEArchiveCacheDecision

    public init(
        operationID: UUID,
        buildNumber: Int,
        officialURL: URL,
        archiveURL: URL,
        byteCount: Int64,
        httpStatus: Int,
        validators: SDEHTTPValidators,
        cacheDecision: SDEArchiveCacheDecision
    ) {
        self.operationID = operationID
        self.buildNumber = buildNumber
        self.officialURL = officialURL
        self.archiveURL = archiveURL
        self.byteCount = byteCount
        self.httpStatus = httpStatus
        self.validators = validators
        self.cacheDecision = cacheDecision
    }
}

public struct SDEArchiveInspection: Equatable, Sendable {
    public let entryCount: Int
    public let compressedByteCount: Int64
    public let uncompressedByteCount: Int64
    public let requiredDatasetFileNames: Set<String>

    public init(
        entryCount: Int,
        compressedByteCount: Int64,
        uncompressedByteCount: Int64,
        requiredDatasetFileNames: Set<String>
    ) {
        self.entryCount = entryCount
        self.compressedByteCount = compressedByteCount
        self.uncompressedByteCount = uncompressedByteCount
        self.requiredDatasetFileNames = requiredDatasetFileNames
    }
}

public struct SDEPreparedArchive: Equatable, Sendable {
    public let extractedDirectoryURL: URL
    public let inspection: SDEArchiveInspection

    public init(
        extractedDirectoryURL: URL,
        inspection: SDEArchiveInspection
    ) {
        self.extractedDirectoryURL = extractedDirectoryURL
        self.inspection = inspection
    }
}

public protocol SDEArchiveDownloading: Sendable {
    func download(_ request: SDEArchiveDownloadRequest) async throws
        -> SDEArchiveDownload
    func cleanup(operationID: UUID) async throws
}

public protocol SDEArchivePreparing: Sendable {
    func prepare(_ download: SDEArchiveDownload) async throws
        -> SDEPreparedArchive
    func cleanup(operationID: UUID) async throws
}

public struct SDEStagingValidationResult: Equatable, Sendable {
    public let buildNumber: Int
    public let counts: StaticDataCatalogCounts
    public let reopenedSuccessfully: Bool

    public init(
        buildNumber: Int,
        counts: StaticDataCatalogCounts,
        reopenedSuccessfully: Bool
    ) {
        self.buildNumber = buildNumber
        self.counts = counts
        self.reopenedSuccessfully = reopenedSuccessfully
    }
}

public protocol StaticDataCatalogStaging: Sendable {
    func validateInIsolatedStore(
        _ snapshot: StaticDataCatalogSnapshot,
        operationID: UUID
    ) async throws -> SDEStagingValidationResult
    func cleanup(operationID: UUID) async throws
}

public protocol StaticDataCatalogStreamingStaging: Sendable {
    func validateStreamingInIsolatedStore(
        packageURL: URL,
        mapper: any StaticDataCatalogStreamingMapping,
        batchSize: Int,
        operationID: UUID
    ) async throws -> SDEStagingValidationResult
}

public protocol SDEPromotionSafetyBackingUp: Sendable {
    func createSafetyBackup(operationID: UUID) async throws -> Bool
}

public protocol StaticDataCatalogRollingBack: Sendable {
    func rollback(toBuildNumber buildNumber: Int) async throws
        -> StaticDataActivationResult
}

public struct SDEInstallationEvent: Codable, Equatable, Sendable {
    public let phase: SDEInstallationPhase
    public let occurredAt: Date
    public let safeCode: String?

    public init(
        phase: SDEInstallationPhase,
        occurredAt: Date,
        safeCode: String? = nil
    ) {
        self.phase = phase
        self.occurredAt = occurredAt
        self.safeCode = safeCode
    }
}

public struct SDEInstallationLog: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let requestedBuildNumber: Int
    public var previousActiveBuildNumber: Int?
    public var activatedBuildNumber: Int?
    public var officialURL: String
    public var httpStatus: Int?
    public var cacheDecision: SDEArchiveCacheDecision?
    public var downloadByteCount: Int64?
    public var archiveEntryCount: Int?
    public var archiveUncompressedByteCount: Int64?
    public var counts: StaticDataCatalogCounts?
    public var candidateContentSHA256: String?
    public var parserVersion: Int
    public var importSchemaVersion: Int
    public var backupCreated: Bool
    public var cleanupSucceeded: Bool?
    public var rollbackSucceeded: Bool?
    public var events: [SDEInstallationEvent]

    public init(
        operationID: UUID,
        requestedBuildNumber: Int,
        previousActiveBuildNumber: Int?,
        officialURL: String,
        startedAt: Date
    ) {
        self.operationID = operationID
        self.requestedBuildNumber = requestedBuildNumber
        self.previousActiveBuildNumber = previousActiveBuildNumber
        self.activatedBuildNumber = nil
        self.officialURL = officialURL
        self.httpStatus = nil
        self.cacheDecision = nil
        self.downloadByteCount = nil
        self.archiveEntryCount = nil
        self.archiveUncompressedByteCount = nil
        self.counts = nil
        self.candidateContentSHA256 = nil
        self.parserVersion = 1
        self.importSchemaVersion = 1
        self.backupCreated = false
        self.cleanupSucceeded = nil
        self.rollbackSucceeded = nil
        self.events = [
            SDEInstallationEvent(phase: .started, occurredAt: startedAt)
        ]
    }

    public var isTerminal: Bool {
        guard let phase = events.last?.phase else {
            return false
        }
        return [.completed, .failed, .cancelled, .recovered].contains(phase)
    }
}

public protocol SDEInstallationLogStoring: Sendable {
    func save(_ log: SDEInstallationLog) async throws
    func incompleteLogs() async throws -> [SDEInstallationLog]
}

public typealias SDEInstallationProgressHandler =
    @Sendable (SDEInstallationPhase) -> Void

/// Acceptance-only observation hook invoked after a phase journal was
/// durably written. Production compositions leave this hook unset.
public typealias SDEInstallationCheckpointHandler =
    @Sendable (SDEInstallationPhase, UUID) async throws -> Void

public struct SDEInstallationRequest: Equatable, Sendable {
    public let buildNumber: Int
    public let schemaUnderstoodThroughBuildNumber: Int
    public let ownerComplianceConfirmed: Bool
    public let packageDestinationDirectoryURL: URL

    public init(
        buildNumber: Int,
        schemaUnderstoodThroughBuildNumber: Int,
        ownerComplianceConfirmed: Bool,
        packageDestinationDirectoryURL: URL
    ) {
        self.buildNumber = buildNumber
        self.schemaUnderstoodThroughBuildNumber =
            schemaUnderstoodThroughBuildNumber
        self.ownerComplianceConfirmed = ownerComplianceConfirmed
        self.packageDestinationDirectoryURL =
            packageDestinationDirectoryURL
    }
}

public struct SDEInstallationResult: Equatable, Sendable {
    public let activation: StaticDataActivationResult
    public let backupCreated: Bool
    public let operationID: UUID

    public init(
        activation: StaticDataActivationResult,
        backupCreated: Bool,
        operationID: UUID
    ) {
        self.activation = activation
        self.backupCreated = backupCreated
        self.operationID = operationID
    }
}

public enum SDEInstallationError: Error, Equatable, Sendable {
    case invalidBuildNumber
    case schemaGateRejected
    case ownerComplianceConfirmationRequired
    case invalidOfficialURL
    case missingOwnerContact
    case invalidHTTPStatus(Int)
    case invalidContentType
    case invalidContentLength
    case downloadTooLarge
    case downloadedSizeMismatch
    case insufficientDiskSpace
    case redirectedDownload
    case unsafeArchive
    case damagedArchive
    case encryptedArchive
    case multipartArchive
    case tooManyArchiveEntries
    case archiveEntryTooLarge
    case archiveExpandedSizeTooLarge
    case archiveCompressionRatioTooHigh
    case unsafeArchivePath
    case duplicateArchivePath
    case unexpectedArchiveEntry
    case unsafeArchiveObject
    case missingRequiredDataset(SDEDatasetKind)
    case extractionFailed
    case extractionValidationFailed
    case stagingValidationFailed
    case safetyBackupFailed
    case activationFailed
    case rollbackFailed
    case logPersistenceFailed
    case cleanupFailed
    case transport

    public var safeCode: String {
        switch self {
        case .invalidBuildNumber: "NEN-SDE-007-BUILD"
        case .schemaGateRejected: "NEN-SDE-007-SCHEMA"
        case .ownerComplianceConfirmationRequired: "NEN-SDE-007-COMPLIANCE"
        case .invalidOfficialURL: "NEN-SDE-007-URL"
        case .missingOwnerContact: "NEN-SDE-007-CONTACT"
        case .invalidHTTPStatus(let status): "NEN-SDE-007-HTTP-\(status)"
        case .invalidContentType: "NEN-SDE-007-CONTENT"
        case .invalidContentLength: "NEN-SDE-007-LENGTH"
        case .downloadTooLarge: "NEN-SDE-007-SIZE"
        case .downloadedSizeMismatch: "NEN-SDE-007-SIZE-MISMATCH"
        case .insufficientDiskSpace: "NEN-SDE-007-DISK"
        case .redirectedDownload: "NEN-SDE-007-REDIRECT"
        case .unsafeArchive: "NEN-SDE-007-ZIP"
        case .damagedArchive: "NEN-SDE-007-ZIP-DAMAGED"
        case .encryptedArchive: "NEN-SDE-007-ZIP-ENCRYPTED"
        case .multipartArchive: "NEN-SDE-007-ZIP-MULTIPART"
        case .tooManyArchiveEntries: "NEN-SDE-007-ZIP-COUNT"
        case .archiveEntryTooLarge: "NEN-SDE-007-ZIP-ENTRY-SIZE"
        case .archiveExpandedSizeTooLarge: "NEN-SDE-007-ZIP-TOTAL-SIZE"
        case .archiveCompressionRatioTooHigh: "NEN-SDE-007-ZIP-RATIO"
        case .unsafeArchivePath: "NEN-SDE-007-ZIP-PATH"
        case .duplicateArchivePath: "NEN-SDE-007-ZIP-DUPLICATE"
        case .unexpectedArchiveEntry: "NEN-SDE-007-ZIP-ENTRY"
        case .unsafeArchiveObject: "NEN-SDE-007-ZIP-OBJECT"
        case .missingRequiredDataset(let dataset):
            "NEN-SDE-007-MISSING-\(dataset.rawValue.uppercased())"
        case .extractionFailed: "NEN-SDE-007-EXTRACT"
        case .extractionValidationFailed: "NEN-SDE-007-EXTRACT-VERIFY"
        case .stagingValidationFailed: "NEN-SDE-007-STAGING"
        case .safetyBackupFailed: "NEN-SDE-007-BACKUP"
        case .activationFailed: "NEN-SDE-007-ACTIVATE"
        case .rollbackFailed: "NEN-SDE-007-ROLLBACK"
        case .logPersistenceFailed: "NEN-SDE-007-LOG"
        case .cleanupFailed: "NEN-SDE-007-CLEANUP"
        case .transport: "NEN-SDE-007-TRANSPORT"
        }
    }
}
