import Foundation

public struct AppDataPaths: Equatable, Sendable {
  public enum SwiftDataStoreLocation: String, Sendable {
    case canonical
    case legacyDefaultStore
  }

  public static let applicationIdentifier = "com.local.EVENexusSimple"

  public let applicationSupportRoot: URL
  public let dataRoot: URL
  public let swiftDataStoreURL: URL
  public let swiftDataStoreLocation: SwiftDataStoreLocation
  public let legacySwiftDataStoreURL: URL
  public let sdeRootURL: URL

  public static func live(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> AppDataPaths {
    if let override = environment["EVE_NEXUS_APPLICATION_SUPPORT_ROOT"],
      !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return resolve(
        applicationSupportRoot: URL(
          fileURLWithPath: override,
          isDirectory: true
        ),
        fileExists: fileManager.fileExists(atPath:)
      )
    }
    guard
      let applicationSupportRoot = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw AppDataPathError.applicationSupportUnavailable
    }
    return resolve(
      applicationSupportRoot: applicationSupportRoot,
      fileExists: fileManager.fileExists(atPath:)
    )
  }

  public static func resolve(
    applicationSupportRoot: URL,
    fileExists: (String) -> Bool
  ) -> AppDataPaths {
    let dataRoot = applicationSupportRoot.appendingPathComponent(
      applicationIdentifier,
      isDirectory: true
    )
    let canonicalStore =
      dataRoot
      .appendingPathComponent("ApplicationData", isDirectory: true)
      .appendingPathComponent("EVENexusSimple.store")
    let legacyStore = applicationSupportRoot.appendingPathComponent(
      "default.store"
    )

    return AppDataPaths(
      applicationSupportRoot: applicationSupportRoot,
      dataRoot: dataRoot,
      swiftDataStoreURL: canonicalStore,
      swiftDataStoreLocation: .canonical,
      legacySwiftDataStoreURL: legacyStore,
      sdeRootURL: dataRoot.appendingPathComponent("sde", isDirectory: true)
    )
  }

  public var needsLegacyStoreSeeding: Bool {
    !FileManager.default.fileExists(atPath: swiftDataStoreURL.path)
      && FileManager.default.fileExists(atPath: legacySwiftDataStoreURL.path)
  }

  public func prepareDirectories(
    fileManager: FileManager = .default
  ) throws {
    try fileManager.createDirectory(
      at: dataRoot,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: swiftDataStoreURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: sdeRootURL,
      withIntermediateDirectories: true
    )
  }
}

public enum PersistenceStoreSeeder {
  /// Copies the legacy global SwiftData store into the app-owned location
  /// without changing or removing the source. WAL and shared-memory companions
  /// keep their names so SQLite can recover a consistent snapshot on open.
  public static func seedCanonicalStoreIfNeeded(
    paths: AppDataPaths,
    fileManager: FileManager = .default
  ) throws -> Bool {
    guard !fileManager.fileExists(atPath: paths.swiftDataStoreURL.path),
      fileManager.fileExists(atPath: paths.legacySwiftDataStoreURL.path)
    else { return false }

    try paths.prepareDirectories(fileManager: fileManager)
    for suffix in ["", "-wal", "-shm"] {
      let source = URL(
        fileURLWithPath: paths.legacySwiftDataStoreURL.path + suffix
      )
      guard fileManager.fileExists(atPath: source.path) else { continue }
      let destination = URL(
        fileURLWithPath: paths.swiftDataStoreURL.path + suffix
      )
      guard !fileManager.fileExists(atPath: destination.path) else {
        throw PersistenceStoreSeederError.destinationAlreadyExists
      }
      try fileManager.copyItem(at: source, to: destination)
    }
    return true
  }
}

public enum PersistenceStoreSeederError: Error, Equatable, Sendable {
  case destinationAlreadyExists
}

public enum AppDataPathError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
}

public enum PersistenceSafetyBackup {
  public static func createIfNeeded(
    paths: AppDataPaths,
    schemaVersion: Int,
    fileManager: FileManager = .default,
    now: Date = .now,
    operationID: UUID = UUID()
  ) throws -> URL? {
    guard schemaVersion > 0 else {
      throw PersistenceSafetyBackupError.invalidSchemaVersion
    }
    guard fileManager.fileExists(atPath: paths.swiftDataStoreURL.path) else {
      return nil
    }

    let backupRoot =
      paths.dataRoot
      .appendingPathComponent("migration-backups", isDirectory: true)
      .appendingPathComponent("swiftdata", isDirectory: true)
    try fileManager.createDirectory(
      at: backupRoot,
      withIntermediateDirectories: true
    )
    let marker = backupRoot.appendingPathComponent(
      "\(paths.swiftDataStoreLocation.rawValue)-schema-v\(schemaVersion).complete"
    )
    guard !fileManager.fileExists(atPath: marker.path) else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
      .withInternetDateTime,
      .withDashSeparatorInDate,
      .withColonSeparatorInTime,
    ]
    let directoryName =
      "schema-v\(schemaVersion)-"
      + formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
      + "-\(operationID.uuidString)"
    let destination = backupRoot.appendingPathComponent(
      directoryName,
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: destination,
      withIntermediateDirectories: false
    )

    do {
      let source = paths.swiftDataStoreURL
      for suffix in ["", "-wal", "-shm"] {
        let sourceFile = URL(fileURLWithPath: source.path + suffix)
        guard fileManager.fileExists(atPath: sourceFile.path) else { continue }
        try fileManager.copyItem(
          at: sourceFile,
          to: destination.appendingPathComponent(
            source.lastPathComponent + suffix
          )
        )
      }
      let manifest = PersistenceBackupManifest(
        schemaVersion: schemaVersion,
        createdAt: now,
        sourceFileName: source.lastPathComponent,
        sourceLocation: paths.swiftDataStoreLocation.rawValue
      )
      let encoded = try JSONEncoder().encode(manifest)
      try encoded.write(
        to: destination.appendingPathComponent("manifest.json"),
        options: .atomic
      )
      try Data(destination.lastPathComponent.utf8).write(
        to: marker,
        options: .atomic
      )
      return destination
    } catch {
      throw PersistenceSafetyBackupError.backupFailed
    }
  }
}

private struct PersistenceBackupManifest: Codable {
  let schemaVersion: Int
  let createdAt: Date
  let sourceFileName: String
  let sourceLocation: String
}

public enum PersistenceSafetyBackupError: Error, Equatable, Sendable {
  case invalidSchemaVersion
  case backupFailed
}
