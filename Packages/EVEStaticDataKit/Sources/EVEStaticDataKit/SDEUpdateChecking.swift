import Foundation

public enum SDEUpdateCheckStatus: String, Codable, CaseIterable, Sendable {
    case current
    case updateAvailable = "update_available"
    case notModified = "not_modified"
    case offline
    case schemaReviewRequired = "schema_review_required"
    case failed
}

public enum SDEUpdateCheckExecution: String, Codable, Sendable {
    case network
    case localMinimumInterval = "local_minimum_interval"
    case serverCache = "server_cache"
}

public enum SDEHTTPResource: String, Codable, CaseIterable, Sendable {
    case latestBuild = "latest_build"
    case schemaChangelog = "schema_changelog"
}

public struct SDEHTTPValidators: Codable, Equatable, Sendable {
    public let etag: String?
    public let lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }

    public var isEmpty: Bool {
        etag == nil && lastModified == nil
    }
}

public struct SDEHTTPCacheMetadata: Codable, Equatable, Sendable {
    public let validators: SDEHTTPValidators
    public let freshUntil: Date?

    public init(
        validators: SDEHTTPValidators = SDEHTTPValidators(),
        freshUntil: Date? = nil
    ) {
        self.validators = validators
        self.freshUntil = freshUntil
    }
}

public struct SDEHTTPResponseMetadata: Equatable, Sendable {
    public let statusCode: Int
    public let cache: SDEHTTPCacheMetadata

    public init(statusCode: Int, cache: SDEHTTPCacheMetadata) {
        self.statusCode = statusCode
        self.cache = cache
    }
}

public struct SDEReleaseMetadata: Equatable, Sendable {
    public let buildNumber: Int
    public let releasedAt: Date

    public init(buildNumber: Int, releasedAt: Date) throws {
        guard buildNumber > 0 else {
            throw SDEUpdateConfigurationError.invalidBuildNumber
        }
        self.buildNumber = buildNumber
        self.releasedAt = releasedAt
    }
}

public struct SDESchemaChangelogSummary: Equatable, Sendable {
    public let highestAfterBuildNumber: Int
    public let entryCount: Int
    public let parserVersion: Int

    public init(
        highestAfterBuildNumber: Int,
        entryCount: Int,
        parserVersion: Int
    ) throws {
        guard highestAfterBuildNumber > 0, entryCount > 0, parserVersion > 0 else {
            throw SDEUpdateConfigurationError.invalidSchemaSummary
        }
        self.highestAfterBuildNumber = highestAfterBuildNumber
        self.entryCount = entryCount
        self.parserVersion = parserVersion
    }
}

public enum SDEMetadataFetchResult<Payload: Equatable & Sendable>:
    Equatable,
    Sendable {
    case modified(Payload, SDEHTTPResponseMetadata)
    case notModified(SDEHTTPResponseMetadata)

    public var responseMetadata: SDEHTTPResponseMetadata {
        switch self {
        case .modified(_, let metadata), .notModified(let metadata):
            metadata
        }
    }
}

public struct ActiveSDEVersion: Equatable, Sendable {
    public let buildNumber: Int
    public let contentSHA256: String

    public init(buildNumber: Int, contentSHA256: String) throws {
        guard buildNumber > 0 else {
            throw SDEUpdateConfigurationError.invalidBuildNumber
        }
        guard contentSHA256.count == 64,
              contentSHA256.allSatisfy({ $0.isHexDigit }) else {
            throw SDEUpdateConfigurationError.invalidContentHash
        }
        self.buildNumber = buildNumber
        self.contentSHA256 = contentSHA256.lowercased()
    }
}

public struct SDEUpdateCheckState: Equatable, Sendable {
    public var lastAttemptAt: Date?
    public var lastSuccessfulCheckAt: Date?
    public var lastKnownOfficialBuildNumber: Int?
    public var officialReleaseDate: Date?
    public var latestBuildCache: SDEHTTPCacheMetadata
    public var schemaChangelogCache: SDEHTTPCacheMetadata
    public var schemaHighestAfterBuildNumber: Int?
    public var schemaEntryCount: Int?
    public var schemaParserVersion: Int
    public var lastStatus: SDEUpdateCheckStatus?
    public var lastSafeFailureCode: String?

    public init(
        lastAttemptAt: Date? = nil,
        lastSuccessfulCheckAt: Date? = nil,
        lastKnownOfficialBuildNumber: Int? = nil,
        officialReleaseDate: Date? = nil,
        latestBuildCache: SDEHTTPCacheMetadata = SDEHTTPCacheMetadata(),
        schemaChangelogCache: SDEHTTPCacheMetadata = SDEHTTPCacheMetadata(),
        schemaHighestAfterBuildNumber: Int? = nil,
        schemaEntryCount: Int? = nil,
        schemaParserVersion: Int = 1,
        lastStatus: SDEUpdateCheckStatus? = nil,
        lastSafeFailureCode: String? = nil
    ) {
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.lastKnownOfficialBuildNumber = lastKnownOfficialBuildNumber
        self.officialReleaseDate = officialReleaseDate
        self.latestBuildCache = latestBuildCache
        self.schemaChangelogCache = schemaChangelogCache
        self.schemaHighestAfterBuildNumber = schemaHighestAfterBuildNumber
        self.schemaEntryCount = schemaEntryCount
        self.schemaParserVersion = schemaParserVersion
        self.lastStatus = lastStatus
        self.lastSafeFailureCode = lastSafeFailureCode
    }
}

public struct SDEUpdateCheckReport: Equatable, Sendable {
    public let status: SDEUpdateCheckStatus
    public let execution: SDEUpdateCheckExecution
    public let localBuildNumber: Int?
    public let officialBuildNumber: Int?
    public let officialReleaseDate: Date?
    public let evaluatedAt: Date
    public let nextEligibleCheckAt: Date?
    public let safeFailureCode: String?

    public init(
        status: SDEUpdateCheckStatus,
        execution: SDEUpdateCheckExecution,
        localBuildNumber: Int?,
        officialBuildNumber: Int?,
        officialReleaseDate: Date?,
        evaluatedAt: Date,
        nextEligibleCheckAt: Date? = nil,
        safeFailureCode: String? = nil
    ) {
        self.status = status
        self.execution = execution
        self.localBuildNumber = localBuildNumber
        self.officialBuildNumber = officialBuildNumber
        self.officialReleaseDate = officialReleaseDate
        self.evaluatedAt = evaluatedAt
        self.nextEligibleCheckAt = nextEligibleCheckAt
        self.safeFailureCode = safeFailureCode
    }
}

public enum SDEUpdateConfigurationError: Error, Equatable, Sendable {
    case invalidBuildNumber
    case invalidContentHash
    case invalidMinimumInterval
    case invalidSchemaCompatibilityBuild
    case invalidSchemaSummary
    case invalidUserAgent
}

public enum SDEMetadataCheckError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case invalidURL
    case invalidValidators
    case invalidContentType
    case responseTooLarge
    case invalidLatestResponse
    case invalidSchemaChangelog
    case invalidCachedState
    case httpStatus(Int)
    case transport

    public var safeCode: String {
        switch self {
        case .offline:
            "NEN-SDE-006-OFFLINE"
        case .timedOut:
            "NEN-SDE-006-TIMEOUT"
        case .invalidURL:
            "NEN-SDE-006-URL"
        case .invalidValidators:
            "NEN-SDE-006-CACHE"
        case .invalidContentType:
            "NEN-SDE-006-CONTENT"
        case .responseTooLarge:
            "NEN-SDE-006-SIZE"
        case .invalidLatestResponse:
            "NEN-SDE-006-LATEST"
        case .invalidSchemaChangelog:
            "NEN-SDE-006-SCHEMA"
        case .invalidCachedState:
            "NEN-SDE-006-STATE"
        case .httpStatus(let status):
            "NEN-SDE-006-HTTP-\(status)"
        case .transport:
            "NEN-SDE-006-TRANSPORT"
        }
    }
}

public struct SDEUpdateCheckPolicy: Equatable, Sendable {
    public static let minimumAllowedInterval: TimeInterval = 24 * 60 * 60

    public let minimumCheckInterval: TimeInterval
    public let schemaUnderstoodThroughBuildNumber: Int

    public init(
        minimumCheckInterval: TimeInterval = Self.minimumAllowedInterval,
        schemaUnderstoodThroughBuildNumber: Int
    ) throws {
        guard minimumCheckInterval >= Self.minimumAllowedInterval else {
            throw SDEUpdateConfigurationError.invalidMinimumInterval
        }
        guard schemaUnderstoodThroughBuildNumber > 0 else {
            throw SDEUpdateConfigurationError.invalidSchemaCompatibilityBuild
        }
        self.minimumCheckInterval = minimumCheckInterval
        self.schemaUnderstoodThroughBuildNumber =
            schemaUnderstoodThroughBuildNumber
    }
}

public protocol SDEReleaseChecking: Sendable {
    func latestRelease(
        cache: SDEHTTPCacheMetadata?
    ) async throws -> SDEMetadataFetchResult<SDEReleaseMetadata>

    func schemaChangelog(
        cache: SDEHTTPCacheMetadata?
    ) async throws -> SDEMetadataFetchResult<SDESchemaChangelogSummary>
}

public protocol SDEUpdateStateStoring: Sendable {
    func loadState() async throws -> SDEUpdateCheckState
    func saveState(_ state: SDEUpdateCheckState) async throws
}

public protocol ActiveSDEVersionReading: Sendable {
    func activeSDEVersion() async throws -> ActiveSDEVersion?
}

public protocol SDEUpdateClock: Sendable {
    func now() -> Date
}

public struct SystemSDEUpdateClock: SDEUpdateClock {
    public init() {}

    public func now() -> Date {
        Date.now
    }
}

public struct SDEHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let timeout: TimeInterval

    public init(
        url: URL,
        headers: [String: String],
        timeout: TimeInterval
    ) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }
}

public struct SDEHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data
    public let finalURL: URL?

    public init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        finalURL: URL? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { result, element in
            result[element.key.lowercased()] = element.value
        }
        self.body = body
        self.finalURL = finalURL
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol SDEHTTPTransport: Sendable {
    func execute(_ request: SDEHTTPRequest) async throws -> SDEHTTPResponse
}

public protocol SDEBackoffSleeping: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public protocol SDEJitterGenerating: Sendable {
    func unitInterval() -> Double
}

public struct SDEUserAgentConfiguration: Equatable, Sendable {
    public let applicationName: String
    public let applicationVersion: String
    public let contact: String?
    public let purpose: String

    public init(
        applicationName: String,
        applicationVersion: String,
        contact: String? = nil,
        purpose: String = "SDE integration"
    ) throws {
        let name = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = applicationVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContact = contact?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedPurpose = purpose.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard Self.isSafeToken(name), Self.isSafeToken(version),
              Self.isSafeComment(normalizedPurpose),
              normalizedContact.map(Self.isSafeComment) ?? true else {
            throw SDEUpdateConfigurationError.invalidUserAgent
        }
        self.applicationName = name
        self.applicationVersion = version
        self.contact = normalizedContact?.isEmpty == false
            ? normalizedContact
            : nil
        self.purpose = normalizedPurpose
    }

    public var headerValue: String {
        let product = "\(applicationName)/\(applicationVersion)"
        guard let contact else {
            return "\(product) (\(purpose))"
        }
        return "\(product) (\(purpose); contact: \(contact))"
    }

    private static func isSafeToken(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { character in
            !character.isWhitespace && !character.isNewline
                && character != "(" && character != ")"
                && character != ";" && character.asciiValue.map {
                    $0 >= 33 && $0 <= 126
                } == true
        }
    }

    private static func isSafeComment(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 && scalar.value <= 126
                && scalar != "(" && scalar != ")"
        }
    }
}

public struct SDEUpdateService: Sendable {
    private let checker: any SDEReleaseChecking
    private let stateStore: any SDEUpdateStateStoring
    private let activeVersionReader: any ActiveSDEVersionReading
    private let clock: any SDEUpdateClock
    private let policy: SDEUpdateCheckPolicy
    private let logger: any DiagnosticLogging
    private let makeCorrelationID: @Sendable () -> UUID

    public init(
        checker: any SDEReleaseChecking,
        stateStore: any SDEUpdateStateStoring,
        activeVersionReader: any ActiveSDEVersionReading,
        clock: any SDEUpdateClock = SystemSDEUpdateClock(),
        policy: SDEUpdateCheckPolicy,
        logger: any DiagnosticLogging,
        makeCorrelationID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.checker = checker
        self.stateStore = stateStore
        self.activeVersionReader = activeVersionReader
        self.clock = clock
        self.policy = policy
        self.logger = logger
        self.makeCorrelationID = makeCorrelationID
    }

    public func check(force: Bool = false) async throws -> SDEUpdateCheckReport {
        try Task.checkCancellation()
        let now = clock.now()
        var state = try await stateStore.loadState()
        let activeVersion = try await activeVersionReader.activeSDEVersion()

        if let deferred = deferredReport(
            state: state,
            activeVersion: activeVersion,
            now: now,
            force: force
        ) {
            log(
                level: .info,
                name: "sde_update_check_deferred",
                status: deferred.status,
                localBuild: deferred.localBuildNumber,
                officialBuild: deferred.officialBuildNumber
            )
            return deferred
        }

        state.lastAttemptAt = now
        try await stateStore.saveState(state)

        do {
            let releaseFetch = try await releaseFetch(
                state: state,
                now: now
            )
            let release = try resolveRelease(releaseFetch, state: &state)

            let schemaFetch = try await schemaFetch(
                state: state,
                now: now
            )
            let schema = try resolveSchema(schemaFetch, state: &state)

            let bothNotModified =
                releaseFetch.isNotModified && schemaFetch.isNotModified
            let status = resolvedStatus(
                localBuild: activeVersion?.buildNumber,
                officialBuild: release.buildNumber,
                schema: schema,
                bothNotModified: bothNotModified
            )
            state.lastSuccessfulCheckAt = now
            state.lastStatus = status
            state.lastSafeFailureCode = nil
            try await stateStore.saveState(state)

            let report = SDEUpdateCheckReport(
                status: status,
                execution: .network,
                localBuildNumber: activeVersion?.buildNumber,
                officialBuildNumber: release.buildNumber,
                officialReleaseDate: release.releasedAt,
                evaluatedAt: now
            )
            log(
                level: status == .schemaReviewRequired ? .warning : .info,
                name: "sde_update_check_completed",
                status: status,
                localBuild: activeVersion?.buildNumber,
                officialBuild: release.buildNumber
            )
            return report
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let typedError = error as? SDEMetadataCheckError ?? .transport
            let status: SDEUpdateCheckStatus =
                typedError == .offline ? .offline : .failed
            state.lastStatus = status
            state.lastSafeFailureCode = typedError.safeCode
            try await stateStore.saveState(state)
            log(
                level: .warning,
                name: "sde_update_check_failed",
                status: status,
                localBuild: activeVersion?.buildNumber,
                officialBuild: state.lastKnownOfficialBuildNumber,
                failureCode: typedError.safeCode
            )
            return SDEUpdateCheckReport(
                status: status,
                execution: .network,
                localBuildNumber: activeVersion?.buildNumber,
                officialBuildNumber: state.lastKnownOfficialBuildNumber,
                officialReleaseDate: state.officialReleaseDate,
                evaluatedAt: now,
                safeFailureCode: typedError.safeCode
            )
        }
    }

    private func deferredReport(
        state: SDEUpdateCheckState,
        activeVersion: ActiveSDEVersion?,
        now: Date,
        force: Bool
    ) -> SDEUpdateCheckReport? {
        if !force, let lastAttemptAt = state.lastAttemptAt {
            let eligibleAt = lastAttemptAt.addingTimeInterval(
                policy.minimumCheckInterval
            )
            if now < eligibleAt {
                return SDEUpdateCheckReport(
                    status: state.lastStatus ?? .notModified,
                    execution: .localMinimumInterval,
                    localBuildNumber: activeVersion?.buildNumber,
                    officialBuildNumber: state.lastKnownOfficialBuildNumber,
                    officialReleaseDate: state.officialReleaseDate,
                    evaluatedAt: now,
                    nextEligibleCheckAt: eligibleAt,
                    safeFailureCode: state.lastSafeFailureCode
                )
            }
        }

        let freshness = [
            state.latestBuildCache.freshUntil,
            state.schemaChangelogCache.freshUntil
        ]
        .compactMap { $0 }
        if freshness.count == 2,
           let freshUntil = freshness.min(),
           now < freshUntil {
            return SDEUpdateCheckReport(
                status: state.lastStatus ?? .notModified,
                execution: .serverCache,
                localBuildNumber: activeVersion?.buildNumber,
                officialBuildNumber: state.lastKnownOfficialBuildNumber,
                officialReleaseDate: state.officialReleaseDate,
                evaluatedAt: now,
                nextEligibleCheckAt: freshUntil,
                safeFailureCode: state.lastSafeFailureCode
            )
        }
        return nil
    }

    private func releaseFetch(
        state: SDEUpdateCheckState,
        now: Date
    ) async throws -> SDEMetadataFetchResult<SDEReleaseMetadata> {
        if let freshUntil = state.latestBuildCache.freshUntil,
           now < freshUntil {
            return .notModified(
                SDEHTTPResponseMetadata(
                    statusCode: 304,
                    cache: state.latestBuildCache
                )
            )
        }
        return try await checker.latestRelease(
            cache: state.latestBuildCache
        )
    }

    private func schemaFetch(
        state: SDEUpdateCheckState,
        now: Date
    ) async throws -> SDEMetadataFetchResult<SDESchemaChangelogSummary> {
        if let freshUntil = state.schemaChangelogCache.freshUntil,
           now < freshUntil {
            return .notModified(
                SDEHTTPResponseMetadata(
                    statusCode: 304,
                    cache: state.schemaChangelogCache
                )
            )
        }
        return try await checker.schemaChangelog(
            cache: state.schemaChangelogCache
        )
    }

    private func resolveRelease(
        _ fetch: SDEMetadataFetchResult<SDEReleaseMetadata>,
        state: inout SDEUpdateCheckState
    ) throws -> SDEReleaseMetadata {
        state.latestBuildCache = fetch.responseMetadata.cache
        switch fetch {
        case .modified(let release, _):
            state.lastKnownOfficialBuildNumber = release.buildNumber
            state.officialReleaseDate = release.releasedAt
            return release
        case .notModified:
            guard let buildNumber = state.lastKnownOfficialBuildNumber,
                  let releasedAt = state.officialReleaseDate else {
                throw SDEMetadataCheckError.invalidCachedState
            }
            return try SDEReleaseMetadata(
                buildNumber: buildNumber,
                releasedAt: releasedAt
            )
        }
    }

    private func resolveSchema(
        _ fetch: SDEMetadataFetchResult<SDESchemaChangelogSummary>,
        state: inout SDEUpdateCheckState
    ) throws -> SDESchemaChangelogSummary {
        state.schemaChangelogCache = fetch.responseMetadata.cache
        switch fetch {
        case .modified(let summary, _):
            state.schemaHighestAfterBuildNumber =
                summary.highestAfterBuildNumber
            state.schemaEntryCount = summary.entryCount
            state.schemaParserVersion = summary.parserVersion
            return summary
        case .notModified:
            guard let highest = state.schemaHighestAfterBuildNumber,
                  let entryCount = state.schemaEntryCount else {
                throw SDEMetadataCheckError.invalidCachedState
            }
            return try SDESchemaChangelogSummary(
                highestAfterBuildNumber: highest,
                entryCount: entryCount,
                parserVersion: state.schemaParserVersion
            )
        }
    }

    private func resolvedStatus(
        localBuild: Int?,
        officialBuild: Int,
        schema: SDESchemaChangelogSummary,
        bothNotModified: Bool
    ) -> SDEUpdateCheckStatus {
        if schema.highestAfterBuildNumber
            > policy.schemaUnderstoodThroughBuildNumber {
            return .schemaReviewRequired
        }
        if localBuild == nil || officialBuild > (localBuild ?? 0) {
            return .updateAvailable
        }
        return bothNotModified ? .notModified : .current
    }

    private func log(
        level: DiagnosticLevel,
        name: String,
        status: SDEUpdateCheckStatus,
        localBuild: Int?,
        officialBuild: Int?,
        failureCode: String? = nil
    ) {
        var metadata: [String: DiagnosticValue] = [
            "status": .publicValue(status.rawValue)
        ]
        if let localBuild {
            metadata["local_build"] = .publicValue(String(localBuild))
        }
        if let officialBuild {
            metadata["official_build"] = .publicValue(String(officialBuild))
        }
        if let failureCode {
            metadata["failure_code"] = .publicValue(failureCode)
        }
        logger.log(
            DiagnosticEvent(
                level: level,
                category: .staticData,
                name: name,
                code: NexusFailureCode.sdeMetadataCheckFailed.rawValue,
                operation: .sdeMetadataCheck,
                correlationID: makeCorrelationID(),
                metadata: metadata
            )
        )
    }
}

private extension SDEMetadataFetchResult {
    var isNotModified: Bool {
        if case .notModified = self {
            return true
        }
        return false
    }
}
