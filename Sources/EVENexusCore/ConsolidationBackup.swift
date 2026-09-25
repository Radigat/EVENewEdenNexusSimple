import CSQLite
import CryptoKit
import Foundation

public struct ConsolidationBackupManifest: Codable, Sendable {
  public let format: Int
  public let dataFamily: String
  public let schema: Int
  public let createdAt: Date
  public let files: [String: String]
}

/// SQLite's online backup API captures committed WAL contents, never a racing copy of db/wal/shm files.
public enum ConsolidationBackup {
  private static let family = "com.local.EVENexusSimple"
  private static let excluded = Set([
    "migration-backups", "backups", "restore-staging", "diagnostics",
  ])
  public static func hash(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var sha = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { sha.update(data: data) }
    return sha.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public static func snapshotSQLite(source: URL, destination: URL) throws {
    guard !FileManager.default.fileExists(atPath: destination.path),
      !FileManager.default.fileExists(atPath: destination.path + "-wal"),
      !FileManager.default.fileExists(atPath: destination.path + "-shm")
    else { throw ConsolidationError.invalid("Sicherungsziel muss neu und unbenutzt sein.") }
    var sourceDB: OpaquePointer?
    var targetDB: OpaquePointer?
    guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      if let sourceDB { sqlite3_close(sourceDB) }
      throw ConsolidationError.unavailable(
        "Datenbank kann nicht für eine Sicherung geöffnet werden.")
    }
    defer { sqlite3_close(sourceDB) }
    guard
      sqlite3_open_v2(destination.path, &targetDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        == SQLITE_OK
    else {
      if let targetDB { sqlite3_close(targetDB) }
      throw ConsolidationError.unavailable("Sicherungsdatenbank kann nicht angelegt werden.")
    }
    defer {
      sqlite3_close(targetDB)
      // This is a newly created offline destination. All committed pages have been
      // checkpointed and its connection is closed before removing transient sidecars.
      for suffix in ["-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: destination.path + suffix)
      }
    }
    guard let backup = sqlite3_backup_init(targetDB, "main", sourceDB, "main") else {
      throw ConsolidationError.unavailable("SQLite-Sicherung nicht verfügbar.")
    }
    var result: Int32 = SQLITE_OK
    var retries = 0
    repeat {
      result = sqlite3_backup_step(backup, 256)
      if result == SQLITE_BUSY || result == SQLITE_LOCKED {
        retries += 1
        sqlite3_sleep(20)
      }
    } while (result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED)
      && retries < 100
    let finish = sqlite3_backup_finish(backup)
    guard result == SQLITE_DONE, finish == SQLITE_OK else {
      throw ConsolidationError.unavailable(
        "Sicherung wegen aktiver Schreibvorgänge abgebrochen. Bitte erneut versuchen.")
    }
    guard
      sqlite3_exec(
        targetDB,
        "PRAGMA journal_mode=WAL; PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE", nil,
        nil, nil) == SQLITE_OK
    else {
      throw ConsolidationError.invalid("Sicherungsjournal konnte nicht abgeschlossen werden.")
    }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(targetDB, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK
    else { throw ConsolidationError.invalid("Sicherungsprüfung fehlgeschlagen.") }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let answer = sqlite3_column_text(statement, 0),
      String(cString: answer) == "ok"
    else { throw ConsolidationError.invalid("SQLite-Sicherung ist nicht konsistent.") }
  }

  public static func create(dataRoot: URL, destination: URL, defaults: Data, schema: Int) throws {
    let fm = FileManager.default
    let dataRoot = dataRoot.standardizedFileURL.resolvingSymlinksInPath()
    let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
    guard !fm.fileExists(atPath: destination.path),
      !destination.standardizedFileURL.path.hasPrefix(dataRoot.standardizedFileURL.path + "/")
    else {
      throw ConsolidationError.invalid(
        "Ein neues Sicherungsziel außerhalb des Datenordners wählen.")
    }
    let staging = destination.deletingLastPathComponent().appendingPathComponent(
      ".eve-backup-\(UUID())")
    try fm.createDirectory(
      at: staging.appendingPathComponent("data"), withIntermediateDirectories: true)
    var finished = false
    defer { if !finished { try? fm.removeItem(at: staging) } }
    var files: [String: String] = [:]
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
    guard let enumerator = fm.enumerator(at: dataRoot, includingPropertiesForKeys: keys) else {
      throw ConsolidationError.unavailable("Datenordner nicht lesbar.")
    }
    for case let file as URL in enumerator {
      let relative = String(
        file.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(dataRoot.path.count + 1))
      if excluded.contains(relative.components(separatedBy: "/")[0]) {
        enumerator.skipDescendants()
        continue
      }
      let values = try file.resourceValues(forKeys: Set(keys))
      guard values.isSymbolicLink != true else {
        throw ConsolidationError.invalid(
          "Symbolische Verknüpfungen im Datenordner werden nicht gesichert.")
      }
      if values.isDirectory == true { continue }
      guard values.isRegularFile == true, !file.lastPathComponent.hasSuffix("-wal"),
        !file.lastPathComponent.hasSuffix("-shm")
      else { continue }
      let target = staging.appendingPathComponent("data").appendingPathComponent(relative)
      try fm.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      let handle = try FileHandle(forReadingFrom: file)
      let header = try handle.read(upToCount: 16)
      try handle.close()
      if header == Data("SQLite format 3\0".utf8) {
        try snapshotSQLite(source: file, destination: target)
      } else {
        try fm.copyItem(at: file, to: target)
      }
      files["data/" + relative] = try hash(target)
    }
    guard files["data/ApplicationData/EVENexusSimple.store"] != nil else {
      throw ConsolidationError.invalid("Die Anwendungsdatenbank fehlt in der Sicherung.")
    }
    try defaults.write(to: staging.appendingPathComponent("preferences.plist"), options: .atomic)
    files["preferences.plist"] = try hash(staging.appendingPathComponent("preferences.plist"))
    let manifest = ConsolidationBackupManifest(
      format: 1, dataFamily: family, schema: schema, createdAt: .now, files: files)
    try JSONEncoder().encode(manifest).write(
      to: staging.appendingPathComponent("manifest.json"), options: .atomic)
    _ = try verify(staging)
    try fm.moveItem(at: staging, to: destination)
    finished = true
  }

  public static func verify(_ folder: URL) throws -> ConsolidationBackupManifest {
    let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
    let manifest = try JSONDecoder().decode(
      ConsolidationBackupManifest.self,
      from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    guard manifest.format == 1, manifest.dataFamily == family, (1...3).contains(manifest.schema),
      manifest.files["data/ApplicationData/EVENexusSimple.store"] != nil,
      manifest.files["preferences.plist"] != nil
    else {
      throw ConsolidationError.invalid(
        "Fremdes oder nicht unterstütztes Sicherungsformat. Legacy-Nexus-Datenbanken werden nicht importiert."
      )
    }
    let root = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    for (relative, expected) in manifest.files {
      let components = relative.split(separator: "/")
      guard !relative.hasPrefix("/"), !components.contains(".."), !components.contains("."),
        relative == "preferences.plist" || relative.hasPrefix("data/"), expected.count == 64
      else { throw ConsolidationError.invalid("Ungültiger Sicherungspfad.") }
      let file = folder.appendingPathComponent(relative)
      guard file.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root),
        try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]).isRegularFile
          == true,
        try hash(file) == expected
      else {
        throw ConsolidationError.invalid(
          "Prüfsumme oder Dateipfad der Sicherung stimmt nicht: \(relative)")
      }
    }
    // Reject unlisted files so a restore cannot smuggle unrelated state into the data root.
    let enumerator = FileManager.default.enumerator(
      at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    while let file = enumerator?.nextObject() as? URL {
      let v = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard v.isSymbolicLink != true else {
        throw ConsolidationError.invalid("Verknüpfung in der Sicherung.")
      }
      if v.isRegularFile == true {
        let relative = String(
          file.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(folder.path.count + 1))
        guard relative == "manifest.json" || manifest.files[relative] != nil else {
          throw ConsolidationError.invalid(
            "Nicht verzeichnete Datei in der Sicherung \(folder.lastPathComponent): \(relative)")
        }
      }
    }
    return manifest
  }

  /// Stage a verified copy. The live container is never replaced while open.
  public static func scheduleRestore(_ folder: URL, paths: AppDataPaths) throws {
    _ = try verify(folder)
    let fm = FileManager.default
    let staged = paths.applicationSupportRoot.appendingPathComponent(".eve-restore-\(UUID())")
    try fm.copyItem(at: folder, to: staged)
    do {
      _ = try verify(staged)
      try Data(staged.lastPathComponent.utf8).write(to: requestURL(paths), options: .atomic)
    } catch {
      try? fm.removeItem(at: staged)
      throw error
    }
  }
  public static func applyPendingRestore(paths: AppDataPaths, defaults: Data, schema: Int) throws
    -> Data?
  {
    let fm = FileManager.default
    let request = requestURL(paths)
    guard fm.fileExists(atPath: request.path) else { return nil }
    let name = try String(contentsOf: request, encoding: .utf8)
    guard name.hasPrefix(".eve-restore-"),
      UUID(uuidString: String(name.dropFirst(".eve-restore-".count))) != nil
    else { throw ConsolidationError.invalid("Ungültiger Wiederherstellungsauftrag.") }
    let staged = paths.applicationSupportRoot.appendingPathComponent(name)
    _ = try verify(staged)
    let preferences = try Data(contentsOf: staged.appendingPathComponent("preferences.plist"))
    _ = try PropertyListSerialization.propertyList(from: preferences, options: [], format: nil)
    let backup = paths.applicationSupportRoot.appendingPathComponent(
      "EVE-before-restore-\(UUID()).nexusbackup")
    try create(dataRoot: paths.dataRoot, destination: backup, defaults: defaults, schema: schema)
    let prior = paths.applicationSupportRoot.appendingPathComponent(".eve-prior-\(UUID())")
    try fm.moveItem(at: paths.dataRoot, to: prior)
    do {
      try fm.moveItem(at: staged.appendingPathComponent("data"), to: paths.dataRoot)
      try fm.removeItem(at: request)
    } catch {
      if fm.fileExists(atPath: paths.dataRoot.path) {
        try? fm.moveItem(at: paths.dataRoot, to: staged.appendingPathComponent("data"))
      }
      try fm.moveItem(at: prior, to: paths.dataRoot)
      throw error
    }
    // Retain both the verified backup and prior directory for recovery; no user data is deleted.
    return preferences
  }
  private static func requestURL(_ paths: AppDataPaths) -> URL {
    paths.applicationSupportRoot.appendingPathComponent(".eve-restore-request")
  }
}
