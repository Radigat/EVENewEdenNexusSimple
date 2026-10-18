import CryptoKit
import Darwin
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
  /// Publish a closed standalone snapshot in one no-overwrite filesystem operation.
  /// An interrupted preparation never leaves a canonical main file behind.
  public static func seedCanonicalStoreIfNeeded(
    paths: AppDataPaths,
    fileManager: FileManager = .default
  ) throws -> Bool {
    guard !fileManager.fileExists(atPath: paths.swiftDataStoreURL.path),
      fileManager.fileExists(atPath: paths.legacySwiftDataStoreURL.path)
    else { return false }
    try paths.prepareDirectories(fileManager: fileManager)
    func checkCompanions() throws {
      for suffix in ["-wal", "-shm", "-journal"] {
        guard !fileManager.fileExists(atPath: paths.swiftDataStoreURL.path + suffix) else {
          throw PersistenceStoreSeederError.destinationAlreadyExists
        }
      }
    }
    try checkCompanions()
    let staged = paths.swiftDataStoreURL.deletingLastPathComponent()
      .appendingPathComponent(".seed-\(UUID()).store")
    defer {
      for suffix in ["", "-wal", "-shm", "-journal"] {
        try? fileManager.removeItem(atPath: staged.path + suffix)
      }
    }
    try ConsolidationBackup.snapshotSQLite(source: paths.legacySwiftDataStoreURL, destination: staged)
    try checkCompanions()
    guard link(staged.path, paths.swiftDataStoreURL.path) == 0 else {
      throw PersistenceStoreSeederError.destinationAlreadyExists
    }
    try PersistenceDurability.syncDirectory(paths.swiftDataStoreURL.deletingLastPathComponent())
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
      try ConsolidationBackup.snapshotSQLite(
        source: source,
        destination: destination.appendingPathComponent(source.lastPathComponent)
      )
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

/// Initializes the isolated DEV copy before the native SwiftUI app is constructed.
public enum DevelopmentAppBootstrap {
  private struct SeedManifest: Codable {
    let format: Int
    let files: [String: String]
  }

  private enum LaunchError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
      switch self {
      case .invalid(let message): return message
      }
    }
  }

  private static func hash(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func verify(_ inputFolder: URL) throws -> SeedManifest {
    let folder = inputFolder.standardizedFileURL.resolvingSymlinksInPath()
    let fm = FileManager.default
    let manifest = try JSONDecoder().decode(
      SeedManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    guard manifest.format == 1,
      manifest.files["data/ApplicationData/EVENexusSimple.store"] != nil,
      manifest.files["preferences.plist"] != nil
    else { throw LaunchError.invalid("Die DEV-Datenkopie ist unvollständig.") }
    guard
      let entries = fm.enumerator(
        at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
    else { throw LaunchError.invalid("Die DEV-Datenkopie ist nicht lesbar.") }
    var found = Set<String>()
    for case let file as URL in entries {
      let properties = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
      guard properties.isSymbolicLink != true else {
        throw LaunchError.invalid("Verknüpfung in der DEV-Datenkopie.")
      }
      guard properties.isRegularFile == true else { continue }
      let relative = String(
        file.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(folder.path.count + 1))
      if relative == "manifest.json" { continue }
      guard let expected = manifest.files[relative], try hash(file) == expected else {
        throw LaunchError.invalid("Die DEV-Datenkopie hat eine ungültige Prüfsumme.")
      }
      found.insert(relative)
    }
    guard found == Set(manifest.files.keys) else {
      throw LaunchError.invalid("In der DEV-Datenkopie fehlen Dateien.")
    }
    return manifest
  }

  /// Resolve DEV isolation before acquiring the persistence lock or doing any disk mutation.
  public static func configurePaths() throws {
    let environment = ProcessInfo.processInfo.environment
    let identifier = Bundle.main.bundleIdentifier ?? ""
    let acceptance = environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1"
    guard identifier == "com.local.EVENexusSimple.DEV"
      || (acceptance && identifier.hasPrefix("com.local.EVENexusSimple.DEV.fixture.")) else { return }
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw AppDataPathError.applicationSupportUnavailable
    }
    let override = acceptance ? environment["EVE_NEXUS_DEV_ACCEPTANCE_ROOT"] : nil
    let root = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? support.appendingPathComponent(identifier, isDirectory: true)
    let preferencesDomain = override == nil ? identifier : identifier + ".smoke." + root.lastPathComponent
    setenv("EVE_NEXUS_APPLICATION_SUPPORT_ROOT", root.path, 1)
    setenv("EVE_NEXUS_USER_DEFAULTS_SUITE", preferencesDomain, 1)
  }

  public static func prepare() throws {
    let fm = FileManager.default
    let developmentIdentifier = "com.local.EVENexusSimple.DEV"
    let environment = ProcessInfo.processInfo.environment
    let acceptance = environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1"
    let bundleID = Bundle.main.bundleIdentifier ?? ""
    let syntheticIdentity = acceptance && bundleID.hasPrefix(developmentIdentifier + ".fixture.")
    guard bundleID == developmentIdentifier || syntheticIdentity else { return }
    guard let resources = Bundle.main.resourceURL else {
      throw LaunchError.invalid("Ungültiges DEV-App-Paket.")
    }
    let identifier = bundleID
    // The optional override is only accepted during the isolated packaging smoke test.
    let override = acceptance ? environment["EVE_NEXUS_DEV_ACCEPTANCE_ROOT"] : nil
    let support = try fm.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    let root =
      override.map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? support.appendingPathComponent(identifier, isDirectory: true)
    let preferencesDomain =
      override == nil ? identifier : identifier + ".smoke." + root.lastPathComponent
    let marker = root.appendingPathComponent("dev-seed-complete.json")
    let dataRoot = root.appendingPathComponent("com.local.EVENexusSimple", isDirectory: true)

    if !fm.fileExists(atPath: root.path) {
      let seed = resources.appendingPathComponent("DevSeed", isDirectory: true)
      _ = try verify(seed)
      let stage = root.deletingLastPathComponent().appendingPathComponent(".eve-dev-seed-\(UUID())")
      defer { try? fm.removeItem(at: stage) }
      try fm.copyItem(at: seed, to: stage)
      _ = try verify(stage)
      try fm.moveItem(
        at: stage.appendingPathComponent("data"),
        to: stage.appendingPathComponent("com.local.EVENexusSimple"))
      try fm.moveItem(
        at: stage.appendingPathComponent("manifest.json"),
        to: stage.appendingPathComponent("dev-seed-complete.json"))
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
      try fm.moveItem(at: stage, to: root)
    }

    guard fm.fileExists(atPath: marker.path),
      fm.fileExists(
        atPath: dataRoot.appendingPathComponent("ApplicationData/EVENexusSimple.store").path),
      try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
      try dataRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
    else {
      throw LaunchError.invalid(
        "Der DEV-Datenordner ist unvollständig. Bestehende Daten wurden nicht überschrieben.")
    }
    let preferencesMarker = root.appendingPathComponent("dev-preferences-imported")
    if !fm.fileExists(atPath: preferencesMarker.path) {
      let data = try Data(contentsOf: root.appendingPathComponent("preferences.plist"))
      guard
        let preferences = try PropertyListSerialization.propertyList(
          from: data, options: [], format: nil) as? [String: Any]
      else { throw LaunchError.invalid("DEV-Einstellungen sind nicht lesbar.") }
      let defaults: UserDefaults
      if preferencesDomain == Bundle.main.bundleIdentifier {
        // macOS rejects the current bundle ID as an additional suite. Its own
        // preferences are the standard domain, including for the separate DEV app.
        defaults = .standard
      } else if let suite = UserDefaults(suiteName: preferencesDomain) {
        defaults = suite
      } else {
        throw LaunchError.invalid("Der DEV-Einstellungsbereich konnte nicht geöffnet werden.")
      }
      defaults.setPersistentDomain(preferences, forName: preferencesDomain)
      guard defaults.synchronize() else {
        throw LaunchError.invalid("DEV-Einstellungen konnten nicht gespeichert werden.")
      }
      try Data().write(to: preferencesMarker, options: .atomic)
    }

    // Always set both: inherited production paths must never leak into this variant.
    setenv("EVE_NEXUS_APPLICATION_SUPPORT_ROOT", root.path, 1)
    setenv("EVE_NEXUS_USER_DEFAULTS_SUITE", preferencesDomain, 1)
  }
}
