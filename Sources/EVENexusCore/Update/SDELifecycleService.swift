import EVEStaticDataKit
import Foundation

public struct SDEUpdatePreview: Equatable, Sendable {
  public let activeBuild: Int?
  public let officialBuild: Int
  public let releasedAt: Date
  public let schemaHighestAfterBuild: Int
  public let schemaEntryCount: Int
  public let requiresUpdate: Bool
  public let requiresSchemaReview: Bool
}

public struct SDEActivationSummary: Equatable, Sendable {
  public let buildNumber: Int
  public let contentSHA256: String
  public let backupCreated: Bool
  public let counts: StaticDataCatalogCounts
}

public enum SDELifecycleError: Error, Equatable, Sendable {
  case metadataNotModifiedWithoutCache
  case confirmationDoesNotMatchPreview
  case schemaReviewNotConfirmed
}

public actor SDELifecycleService {
  private let catalog: SQLiteStaticCatalog
  private let metadataClient: CCPSDEMetadataClient
  private let installer: SDEInstallationService
  private let packageDirectory: URL
  private var latestPreview: SDEUpdatePreview?

  public init(
    rootURL: URL,
    ownerContact: String
  ) throws {
    let userAgent = try SDEUserAgentConfiguration(
      applicationName: "EVE-Nexus-Simple",
      applicationVersion: "1.0",
      contact: ownerContact,
      purpose: "Local SDE integration"
    )
    let catalog = SQLiteStaticCatalog(
      rootURL: rootURL.appendingPathComponent(
        "catalog-store",
        isDirectory: true
      )
    )
    let metadataConfiguration = try CCPSDEMetadataClientConfiguration(
      userAgent: userAgent
    )
    self.metadataClient = CCPSDEMetadataClient(
      transport: URLSessionSDEHTTPTransport(),
      configuration: metadataConfiguration
    )
    let downloaderConfiguration =
      try CCPSDEArchiveDownloaderConfiguration(
        workingDirectoryURL: rootURL.appendingPathComponent(
          "downloads",
          isDirectory: true
        ),
        userAgent: userAgent
      )
    let downloader = CCPSDEArchiveDownloader(
      transport: URLSessionSDEArchiveHTTPTransport(),
      configuration: downloaderConfiguration
    )
    let logStore = FileSDEInstallationLogStore(
      directoryURL: rootURL.appendingPathComponent(
        "installation-logs",
        isDirectory: true
      )
    )
    self.catalog = catalog
    self.packageDirectory = rootURL.appendingPathComponent(
      "packages",
      isDirectory: true
    )
    self.installer = SDEInstallationService(
      downloader: downloader,
      archivePreparer: SecureSDEArchivePreparer(),
      importer: JSONLinesSDEImportService(),
      mapper: JSONLinesSDECatalogMapper(),
      stagingStore: catalog,
      backup: catalog,
      catalogStore: catalog,
      rollbackStore: catalog,
      activeVersionReader: catalog,
      logStore: logStore
    )
  }

  public func check() async throws -> SDEUpdatePreview {
    let releaseFetch = try await metadataClient.latestRelease(cache: nil)
    let schemaFetch = try await metadataClient.schemaChangelog(cache: nil)
    guard case .modified(let release, _) = releaseFetch,
      case .modified(let schema, _) = schemaFetch
    else {
      throw SDELifecycleError.metadataNotModifiedWithoutCache
    }
    let active = try await catalog.activeSDEVersion()
    let preview = SDEUpdatePreview(
      activeBuild: active?.buildNumber,
      officialBuild: release.buildNumber,
      releasedAt: release.releasedAt,
      schemaHighestAfterBuild: schema.highestAfterBuildNumber,
      schemaEntryCount: schema.entryCount,
      requiresUpdate: active?.buildNumber != release.buildNumber,
      requiresSchemaReview:
        schema.highestAfterBuildNumber > (active?.buildNumber ?? 0)
    )
    latestPreview = preview
    return preview
  }

  public func installConfirmed(
    preview: SDEUpdatePreview,
    schemaReviewConfirmed: Bool,
    progress: SDEInstallationProgressHandler? = nil
  ) async throws -> SDEActivationSummary {
    guard latestPreview == preview else {
      throw SDELifecycleError.confirmationDoesNotMatchPreview
    }
    guard !preview.requiresSchemaReview || schemaReviewConfirmed else {
      throw SDELifecycleError.schemaReviewNotConfirmed
    }
    let result = try await installer.install(
      SDEInstallationRequest(
        buildNumber: preview.officialBuild,
        schemaUnderstoodThroughBuildNumber: preview.officialBuild,
        ownerComplianceConfirmed: true,
        packageDestinationDirectoryURL: packageDirectory
      ),
      progress: progress
    )
    latestPreview = nil
    return SDEActivationSummary(
      buildNumber: result.activation.buildNumber,
      contentSHA256: result.activation.contentSHA256,
      backupCreated: result.backupCreated,
      counts: result.activation.counts
    )
  }

  public func recoverInterruptedInstallations() async throws -> Int {
    try await installer.recoverInterruptedInstallations()
  }

  public func activeVersion() async throws -> (Int, String)? {
    guard let version = try await catalog.activeSDEVersion() else {
      return nil
    }
    return (version.buildNumber, version.contentSHA256)
  }

  public func rollback(to buildNumber: Int) async throws
    -> SDEActivationSummary
  {
    let result = try await catalog.rollback(toBuildNumber: buildNumber)
    return SDEActivationSummary(
      buildNumber: result.buildNumber,
      contentSHA256: result.contentSHA256,
      backupCreated: false,
      counts: result.counts
    )
  }
}
