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
  public let sdeRootURL: URL

  public static func live(
    fileManager: FileManager = .default
  ) throws -> AppDataPaths {
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

    let selectedStore: URL
    let selectedLocation: SwiftDataStoreLocation
    if fileExists(canonicalStore.path) {
      selectedStore = canonicalStore
      selectedLocation = .canonical
    } else if fileExists(legacyStore.path) {
      // Existing releases used SwiftData's implicit default.store. Keep using
      // it in place until an explicit, owner-confirmed migration is performed.
      // Opening an empty canonical store would make intact data look lost.
      selectedStore = legacyStore
      selectedLocation = .legacyDefaultStore
    } else {
      selectedStore = canonicalStore
      selectedLocation = .canonical
    }

    return AppDataPaths(
      applicationSupportRoot: applicationSupportRoot,
      dataRoot: dataRoot,
      swiftDataStoreURL: selectedStore,
      swiftDataStoreLocation: selectedLocation,
      sdeRootURL: dataRoot.appendingPathComponent("sde", isDirectory: true)
    )
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
      "schema-v\(schemaVersion).complete"
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
