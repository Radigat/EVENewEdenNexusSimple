import Foundation

public actor SDEInstallationService {
    private let downloader: any SDEArchiveDownloading
    private let archivePreparer: any SDEArchivePreparing
    private let importer: any SDEImporting
    private let mapper: any StaticDataCatalogMapping
    private let stagingStore: any StaticDataCatalogStaging
    private let backup: any SDEPromotionSafetyBackingUp
    private let catalogStore: any StaticDataCatalogStoring
    private let rollbackStore: any StaticDataCatalogRollingBack
    private let activeVersionReader: any ActiveSDEVersionReading
    private let logStore: any SDEInstallationLogStoring
    private let streamingMapper: (any StaticDataCatalogStreamingMapping)?
    private let streamingStagingStore:
        (any StaticDataCatalogStreamingStaging)?
    private let streamingCatalogStore:
        (any StaticDataCatalogStreamingStoring)?
    private let streamingBatchSize: Int
    private let checkpoint: SDEInstallationCheckpointHandler?
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        downloader: any SDEArchiveDownloading,
        archivePreparer: any SDEArchivePreparing,
        importer: any SDEImporting,
        mapper: any StaticDataCatalogMapping,
        stagingStore: any StaticDataCatalogStaging,
        backup: any SDEPromotionSafetyBackingUp,
        catalogStore: any StaticDataCatalogStoring,
        rollbackStore: any StaticDataCatalogRollingBack,
        activeVersionReader: any ActiveSDEVersionReading,
        logStore: any SDEInstallationLogStoring,
        streamingBatchSize: Int = 500,
        checkpoint: SDEInstallationCheckpointHandler? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.downloader = downloader
        self.archivePreparer = archivePreparer
        self.importer = importer
        self.mapper = mapper
        self.stagingStore = stagingStore
        self.backup = backup
        self.catalogStore = catalogStore
        self.rollbackStore = rollbackStore
        self.activeVersionReader = activeVersionReader
        self.logStore = logStore
        self.streamingMapper =
            mapper as? any StaticDataCatalogStreamingMapping
        self.streamingStagingStore =
            stagingStore as? any StaticDataCatalogStreamingStaging
        self.streamingCatalogStore =
            catalogStore as? any StaticDataCatalogStreamingStoring
        self.streamingBatchSize = max(1, streamingBatchSize)
        self.checkpoint = checkpoint
        self.now = now
        self.makeID = makeID
    }

    public func install(
        _ request: SDEInstallationRequest,
        progress: SDEInstallationProgressHandler? = nil
    ) async throws -> SDEInstallationResult {
        guard request.buildNumber > 0 else {
            throw SDEInstallationError.invalidBuildNumber
        }
        guard request.schemaUnderstoodThroughBuildNumber
                >= request.buildNumber else {
            throw SDEInstallationError.schemaGateRejected
        }
        guard request.ownerComplianceConfirmed else {
            throw SDEInstallationError.ownerComplianceConfirmationRequired
        }

        let operationID = makeID()
        let previous = try await activeVersionReader.activeSDEVersion()
        let officialURL = Self.officialArchiveURL(
            buildNumber: request.buildNumber
        )
        var log = SDEInstallationLog(
            operationID: operationID,
            requestedBuildNumber: request.buildNumber,
            previousActiveBuildNumber: previous?.buildNumber,
            officialURL: officialURL,
            startedAt: now()
        )
        guard let streamingMapper,
              let streamingStagingStore,
              let streamingCatalogStore else {
            throw SDEInstallationError.stagingValidationFailed
        }
        log.parserVersion = 2
        log.importSchemaVersion = 2
        try await persistCheckpoint(log)
        progress?(.started)

        do {
            append(.downloading, to: &log)
            progress?(.downloading)
            try await persistCheckpoint(log)
            let download = try await downloader.download(
                SDEArchiveDownloadRequest(
                    operationID: operationID,
                    buildNumber: request.buildNumber
                )
            )
            log.httpStatus = download.httpStatus
            log.cacheDecision = download.cacheDecision
            log.downloadByteCount = download.byteCount

            append(.inspectingArchive, to: &log)
            progress?(.inspectingArchive)
            try await persistCheckpoint(log)
            append(.extractingArchive, to: &log)
            progress?(.extractingArchive)
            try await persistCheckpoint(log)
            let prepared = try await archivePreparer.prepare(download)
            log.archiveEntryCount = prepared.inspection.entryCount
            log.archiveUncompressedByteCount =
                prepared.inspection.uncompressedByteCount

            append(.validatingSource, to: &log)
            progress?(.validatingSource)
            try await persistCheckpoint(log)
            let preview = try await importer.preview(
                sourceDirectoryURL: prepared.extractedDirectoryURL,
                buildNumber: request.buildNumber
            )

            append(.stagingPackage, to: &log)
            progress?(.stagingPackage)
            try await persistCheckpoint(log)
            let package = try await importer.stageImport(
                preview: preview,
                destinationDirectoryURL:
                    request.packageDestinationDirectoryURL
            )

            append(.mappingCatalog, to: &log)
            progress?(.mappingCatalog)
            try await persistCheckpoint(log)
            let metadata = try await streamingMapper.packageMetadata(
                at: package.packageURL
            )
            guard metadata.buildNumber == request.buildNumber else {
                throw SDEInstallationError.stagingValidationFailed
            }
            log.candidateContentSHA256 = metadata.contentSHA256
            append(.validatingStagingStore, to: &log)
            progress?(.validatingStagingStore)
            try await persistCheckpoint(log)
            let staging = try await streamingStagingStore
                .validateStreamingInIsolatedStore(
                    packageURL: package.packageURL,
                    mapper: streamingMapper,
                    batchSize: streamingBatchSize,
                    operationID: operationID
                )
            guard staging.reopenedSuccessfully,
                  staging.buildNumber == request.buildNumber else {
                throw SDEInstallationError.stagingValidationFailed
            }
            let stagedCounts = staging.counts
            log.counts = stagedCounts

            append(.creatingSafetyBackup, to: &log)
            progress?(.creatingSafetyBackup)
            try await persistCheckpoint(log)
            log.backupCreated = try await backup.createSafetyBackup(
                operationID: operationID
            )

            append(.promoting, to: &log)
            progress?(.promoting)
            try await persistCheckpoint(log)
            let activation = try await streamingCatalogStore
                .activateStreaming(
                    packageURL: package.packageURL,
                    mapper: streamingMapper,
                    batchSize: streamingBatchSize
                )
            guard activation.counts == stagedCounts else {
                throw SDEInstallationError.activationFailed
            }
            log.activatedBuildNumber = activation.buildNumber

            append(.completed, to: &log)
            progress?(.completed)
            let cleanupSucceeded = await cleanup(operationID: operationID)
            log.cleanupSucceeded = cleanupSucceeded
            try await persistCheckpoint(log)
            return SDEInstallationResult(
                activation: activation,
                backupCreated: log.backupCreated,
                operationID: operationID
            )
        } catch is CancellationError {
            append(.cancelled, safeCode: "NEN-SDE-007-CANCELLED", to: &log)
            progress?(.cancelled)
            log.cleanupSucceeded = await cleanup(operationID: operationID)
            try? await logStore.save(log)
            throw CancellationError()
        } catch {
            let safeCode = (error as? SDEInstallationError)?.safeCode
                ?? "NEN-SDE-007-FAILED"
            if let previousBuild = log.previousActiveBuildNumber,
               log.events.last?.phase == .promoting {
                log.rollbackSucceeded = (try? await rollbackStore.rollback(
                    toBuildNumber: previousBuild
                )) != nil
            }
            append(.failed, safeCode: safeCode, to: &log)
            progress?(.failed)
            log.cleanupSucceeded = await cleanup(operationID: operationID)
            try? await logStore.save(log)
            throw error
        }
    }

    public func recoverInterruptedInstallations() async throws -> Int {
        let logs = try await logStore.incompleteLogs()
        var recovered = 0
        for var log in logs {
            if let contentSHA256 = log.candidateContentSHA256 {
                do {
                    try await streamingCatalogStore?
                        .discardStreamingImport(
                            contentSHA256: contentSHA256
                        )
                } catch {
                    throw SDEInstallationError.rollbackFailed
                }
            }
            let active = try await activeVersionReader.activeSDEVersion()
            if active?.buildNumber == log.requestedBuildNumber {
                log.activatedBuildNumber = active?.buildNumber
            } else if let previous = log.previousActiveBuildNumber,
                      active?.buildNumber != previous {
                guard (try? await rollbackStore.rollback(
                    toBuildNumber: previous
                )) != nil else {
                    throw SDEInstallationError.rollbackFailed
                }
                log.rollbackSucceeded = true
            }
            log.cleanupSucceeded = await cleanup(
                operationID: log.operationID
            )
            append(.recovered, to: &log)
            try await persist(log)
            recovered += 1
        }
        return recovered
    }

    private static func officialArchiveURL(buildNumber: Int) -> String {
        "https://developers.eveonline.com/static-data/tranquility/"
            + "eve-online-static-data-\(buildNumber)-jsonl.zip"
    }

    private func append(
        _ phase: SDEInstallationPhase,
        safeCode: String? = nil,
        to log: inout SDEInstallationLog
    ) {
        log.events.append(
            SDEInstallationEvent(
                phase: phase,
                occurredAt: now(),
                safeCode: safeCode
            )
        )
    }

    private func persist(_ log: SDEInstallationLog) async throws {
        do {
            try await logStore.save(log)
        } catch {
            throw SDEInstallationError.logPersistenceFailed
        }
    }

    private func persistCheckpoint(
        _ log: SDEInstallationLog
    ) async throws {
        try await persist(log)
        guard let phase = log.events.last?.phase else {
            return
        }
        try await checkpoint?(phase, log.operationID)
    }

    private func cleanup(operationID: UUID) async -> Bool {
        var succeeded = true
        do {
            try await stagingStore.cleanup(operationID: operationID)
        } catch {
            succeeded = false
        }
        do {
            try await archivePreparer.cleanup(operationID: operationID)
        } catch {
            succeeded = false
        }
        do {
            try await downloader.cleanup(operationID: operationID)
        } catch {
            succeeded = false
        }
        return succeeded
    }
}
