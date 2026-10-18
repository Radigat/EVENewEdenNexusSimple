import CSQLite
import CryptoKit
import Darwin
import Foundation

public enum PersistenceDurability {
  public static func syncFile(_ url: URL) throws {
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    defer { Darwin.close(fd) }
    guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
  }
  public static func syncDirectory(_ url: URL) throws { try syncFile(url) }
  public static func write(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try syncFile(url)
    try syncDirectory(url.deletingLastPathComponent())
  }
}

/// Retain for the entire process. The lock lives outside directories that restoration moves.
public final class PersistenceProcessLock {
  private let descriptor: Int32
  public init(paths: AppDataPaths) throws {
    let parent = paths.applicationSupportRoot.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let identity = SHA256.hash(data: Data(paths.dataRoot.standardizedFileURL.resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined()
    descriptor = Darwin.open(parent.appendingPathComponent(".eve-persistence-\(identity).lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      throw ConsolidationError.unavailable("Dieser Datenordner ist bereits in einer anderen App geöffnet. Bitte diese zuerst beenden.")
    }
  }
  /// dup shares the flock's open-file description with the child, including after parent death.
  public func duplicateForChild() throws -> FileHandle {
    let duplicate = dup(descriptor)
    guard duplicate >= 0 else { throw POSIXError(.EIO) }
    return FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
  }
  // Explicit LOCK_UN would also unlock a running validator's inherited description.
  deinit { Darwin.close(descriptor) }
}

public struct FullRestorePreview: Codable, Sendable {
  public let id: UUID
  public let source: URL
  public let backupDirectory: URL
  public let candidateDirectory: URL
  public let modelCounts: [String: Int]
  public let currentSnapshotAvailable: Bool
}

/// Narrow full-store restoration: preferences, Keychain, SDE and secondary stores stay in place.
/// All SwiftData opens are supplied by a short-lived validation process that exits before renames.
public enum StoreFullRestore {
  private struct Journal: Codable {
    let id: UUID
    let originalExisted: Bool
    let importExisted: Bool
    let originalFingerprint: [String: String]?
    let importFingerprint: [String: String]?
    var committed: Bool
  }
  private static var fm: FileManager { .default }
  private static func root(_ paths: AppDataPaths) -> URL {
    paths.dataRoot.appendingPathComponent("full-restore", isDirectory: true)
  }
  private static func request(_ paths: AppDataPaths) -> URL { root(paths).appendingPathComponent("request") }
  private static func journal(_ paths: AppDataPaths) -> URL { root(paths).appendingPathComponent("journal.json") }
  private static func operation(_ paths: AppDataPaths, _ id: UUID) -> URL {
    root(paths).appendingPathComponent(id.uuidString, isDirectory: true)
  }
  private static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
  private static func move(_ source: URL, _ destination: URL) throws {
    // Refuse replacement and cross-volume fallback: each transaction boundary is one rename.
    guard renameatx_np(AT_FDCWD, source.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try PersistenceDurability.syncDirectory(source.deletingLastPathComponent())
    try PersistenceDurability.syncDirectory(destination.deletingLastPathComponent())
  }
  public static func isPending(paths: AppDataPaths) -> Bool { exists(request(paths)) }
  private static func requireNoOtherRestore(_ paths: AppDataPaths) throws {
    guard !exists(paths.applicationSupportRoot.appendingPathComponent(".eve-restore-request")) else {
      throw ConsolidationError.invalid("Ein anderer Sicherungsauftrag ist bereits vorgemerkt. Diesen zuerst abschließen, bevor ein früherer Datenbestand wiederhergestellt wird.")
    }
  }
  public static func schedule(paths: AppDataPaths) throws {
    try requireNoOtherRestore(paths)
    guard !exists(journal(paths)) else { throw ConsolidationError.invalid("Unvollständige Wiederherstellung zuerst prüfen.") }
    guard exists(paths.legacySwiftDataStoreURL) else { throw ConsolidationError.unavailable("Der frühere Datenbestand default.store ist nicht vorhanden.") }
    try fm.createDirectory(at: root(paths), withIntermediateDirectories: true)
    try PersistenceDurability.write(Data("legacy-full-store-v1".utf8), to: request(paths))
  }
  public static func cancel(paths: AppDataPaths) throws {
    guard !exists(journal(paths)) else { throw ConsolidationError.invalid("Laufende Wiederherstellung kann nicht abgebrochen werden.") }
    if exists(request(paths)) { try fm.removeItem(at: request(paths)); try PersistenceDurability.syncDirectory(root(paths)) }
  }
  private static func fingerprint(_ directory: URL) throws -> [String: String] {
    guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else { throw POSIXError(.EIO) }
    var result: [String: String] = [:]
    let prefix = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    for case let file as URL in entries {
      let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw ConsolidationError.invalid("Verknüpfung in Wiederherstellungsdaten.") }
      let path = file.standardizedFileURL.resolvingSymlinksInPath().path
      guard path.hasPrefix(prefix) else { throw POSIXError(.EINVAL) }
      let relative = String(path.dropFirst(prefix.count))
      if values.isDirectory == true { result[relative + "/"] = "directory" }
      else if values.isRegularFile == true { result[relative] = try ConsolidationBackup.hash(file) }
      else { throw ConsolidationError.invalid("Unbekannter Dateityp in Wiederherstellungsdaten.") }
    }
    return result
  }
  private static func syncTree(_ directory: URL) throws {
    guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw POSIXError(.EINVAL) }
    guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else { throw POSIXError(.EIO) }
    var directories = [directory]
    for case let file as URL in entries {
      let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw ConsolidationError.invalid("Verknüpfungen in Anwendungsdaten werden nicht wiederhergestellt.") }
      if values.isRegularFile == true { try PersistenceDurability.syncFile(file) }
      if values.isDirectory == true { directories.append(file) }
    }
    for folder in directories.reversed() { try PersistenceDurability.syncDirectory(folder) }
  }
  private static func rawBundle(source: URL, destination: URL) throws {
    try fm.createDirectory(at: destination, withIntermediateDirectories: false)
    for suffix in ["", "-wal", "-shm", "-journal", "_SUPPORT"] {
      let file = URL(fileURLWithPath: source.path + suffix)
      if exists(file) { try fm.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent)) }
    }
    try syncTree(destination)
  }
  /// Only genuine SQLite corruption permits omitting the current readable snapshot.
  private static func isCorrupt(_ url: URL) throws -> Bool {
    var db: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
    defer { sqlite3_close(db) }
    guard result == SQLITE_OK else {
      if result == SQLITE_CORRUPT || result == SQLITE_NOTADB { return true }
      throw ConsolidationError.unavailable("Aktueller Datenbestand konnte nicht geprüft werden.")
    }
    sqlite3_busy_timeout(db, 5_000)
    var statement: OpaquePointer?
    let prepare = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    if prepare == SQLITE_CORRUPT || prepare == SQLITE_NOTADB { return true }
    guard prepare == SQLITE_OK else { throw ConsolidationError.unavailable("Aktuelle Datenbankprüfung fehlgeschlagen.") }
    let step = sqlite3_step(statement)
    if step == SQLITE_CORRUPT || step == SQLITE_NOTADB { return true }
    guard step == SQLITE_ROW, let answer = sqlite3_column_text(statement, 0) else { throw ConsolidationError.unavailable("Aktuelle Datenbankprüfung blockiert.") }
    return String(cString: answer) != "ok"
  }
  public static func prepare(paths: AppDataPaths, validate: (URL) throws -> [String: Int]) throws -> FullRestorePreview {
    try requireNoOtherRestore(paths)
    guard isPending(paths: paths), !exists(journal(paths)) else { throw ConsolidationError.invalid("Kein exklusiver Wiederherstellungsauftrag vorhanden.") }
    let id = UUID()
    let backup = operation(paths, id)
    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
    try rawBundle(source: paths.legacySwiftDataStoreURL, destination: backup.appendingPathComponent("legacy-raw"))
    let currentFolder = paths.swiftDataStoreURL.deletingLastPathComponent()
    if exists(currentFolder) {
      try fm.copyItem(at: currentFolder, to: backup.appendingPathComponent("current-raw"))
      try syncTree(backup.appendingPathComponent("current-raw"))
    }
    var currentReadable = false
    if exists(paths.swiftDataStoreURL), try !isCorrupt(paths.swiftDataStoreURL) {
      try ConsolidationBackup.snapshotSQLite(source: paths.swiftDataStoreURL, destination: backup.appendingPathComponent("current-readable.store"))
      currentReadable = true
    }
    let legacy = backup.appendingPathComponent("legacy-readable.store")
    try ConsolidationBackup.snapshotSQLite(source: paths.legacySwiftDataStoreURL, destination: legacy)
    let candidate = backup.appendingPathComponent("candidate", isDirectory: true)
    try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
    let store = candidate.appendingPathComponent(paths.swiftDataStoreURL.lastPathComponent)
    try fm.copyItem(at: legacy, to: store)
    let support = URL(fileURLWithPath: paths.legacySwiftDataStoreURL.path + "_SUPPORT")
    if exists(support) { try fm.copyItem(at: support, to: URL(fileURLWithPath: store.path + "_SUPPORT")) }
    let counts = try validate(store)
    try PersistenceDurability.write(Data(id.uuidString.utf8), to: candidate.appendingPathComponent(".full-restore-identity"))
    try syncTree(candidate)
    let preview = FullRestorePreview(id: id, source: paths.legacySwiftDataStoreURL, backupDirectory: backup,
      candidateDirectory: candidate, modelCounts: counts, currentSnapshotAvailable: currentReadable)
    try PersistenceDurability.write(try JSONEncoder().encode(preview), to: backup.appendingPathComponent("preview.json"))
    return preview
  }
  public static func activate(_ preview: FullRestorePreview, paths: AppDataPaths,
    validate: (URL) throws -> [String: Int], boundary: (String) throws -> Void = { _ in }) throws {
    try requireNoOtherRestore(paths)
    let backup = operation(paths, preview.id)
    let candidate = backup.appendingPathComponent("candidate", isDirectory: true)
    guard preview.backupDirectory == backup, preview.candidateDirectory == candidate,
      try String(contentsOf: candidate.appendingPathComponent(".full-restore-identity"), encoding: .utf8) == preview.id.uuidString,
      !exists(journal(paths)), isPending(paths: paths) else { throw ConsolidationError.invalid("Veraltete Wiederherstellungsvorschau.") }
    let active = paths.swiftDataStoreURL.deletingLastPathComponent()
    let pendingImport = paths.dataRoot.appendingPathComponent("recovery-import")
    var state = Journal(id: preview.id, originalExisted: exists(active), importExisted: exists(pendingImport),
      originalFingerprint: exists(active) ? try fingerprint(active) : nil,
      importFingerprint: exists(pendingImport) ? try fingerprint(pendingImport) : nil, committed: false)
    try PersistenceDurability.write(try JSONEncoder().encode(state), to: journal(paths))
    try boundary("journal")
    if state.importExisted { try move(pendingImport, backup.appendingPathComponent("quarantined-recovery-import")) }
    try boundary("import")
    if state.originalExisted { try move(active, backup.appendingPathComponent("original")) }
    try boundary("original")
    try move(preview.candidateDirectory, active)
    try boundary("installed")
    let installed = try validate(paths.swiftDataStoreURL)
    guard installed == preview.modelCounts else { throw ConsolidationError.invalid("Modellzahlen stimmen nach Aktivierung nicht überein.") }
    try syncTree(active)
    state.committed = true
    try PersistenceDurability.write(try JSONEncoder().encode(state), to: journal(paths))
    try boundary("committed")
    try finishCommitted(paths: paths, state: state)
  }
  private static func finishCommitted(paths: AppDataPaths, state: Journal) throws {
    // Archive proof of commit before removing the live journal. Never roll back committed data.
    try PersistenceDurability.write(try JSONEncoder().encode(state), to: operation(paths, state.id).appendingPathComponent("committed.json"))
    if exists(request(paths)) { try fm.removeItem(at: request(paths)); try PersistenceDurability.syncDirectory(root(paths)) }
    try fm.removeItem(at: journal(paths))
    try PersistenceDurability.syncDirectory(root(paths))
  }
  /// Run under the process lock, before opening any canonical container.
  public static func recoverInterrupted(paths: AppDataPaths) throws {
    guard exists(journal(paths)) else { return }
    let state = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journal(paths)))
    if state.committed { try finishCommitted(paths: paths, state: state); return }
    let backup = operation(paths, state.id), active = paths.swiftDataStoreURL.deletingLastPathComponent()
    let original = backup.appendingPathComponent("original")
    let identity = active.appendingPathComponent(".full-restore-identity")
    if exists(active), exists(identity), try String(contentsOf: identity, encoding: .utf8) == state.id.uuidString {
      try move(active, backup.appendingPathComponent("rejected-\(UUID())"))
    }
    if exists(original) {
      guard try fingerprint(original) == state.originalFingerprint else { throw ConsolidationError.invalid("Früherer Bestand stimmt nicht mit dem Wiederherstellungsjournal überein.") }
      guard !exists(active) else { throw ConsolidationError.invalid("Mehrdeutige Wiederherstellung: aktive und frühere Daten bleiben zur Prüfung erhalten.") }
      try move(original, active)
    } else if state.originalExisted {
      guard exists(active), try fingerprint(active) == state.originalFingerprint else {
        throw ConsolidationError.invalid("Frühere Anwendungsdaten fehlen oder sind verändert; Wiederherstellung angehalten.")
      }
    } else if exists(active) {
      throw ConsolidationError.invalid("Unerwarteter aktiver Datenbestand; Wiederherstellung angehalten.")
    }
    let quarantined = backup.appendingPathComponent("quarantined-recovery-import")
    let pending = paths.dataRoot.appendingPathComponent("recovery-import")
    if exists(quarantined) {
      guard try fingerprint(quarantined) == state.importFingerprint else { throw ConsolidationError.invalid("Früherer Import stimmt nicht mit dem Wiederherstellungsjournal überein.") }
      guard !exists(pending) else { throw ConsolidationError.invalid("Mehrdeutiger früherer Import; Wiederherstellung angehalten.") }
      try move(quarantined, pending)
    } else if state.importExisted {
      guard exists(pending), try fingerprint(pending) == state.importFingerprint else { throw ConsolidationError.invalid("Früherer Import fehlt oder ist verändert.") }
    } else if exists(pending) {
      throw ConsolidationError.invalid("Unerwarteter Wiederherstellungsimport bleibt zur Prüfung erhalten.")
    }
    try fm.removeItem(at: journal(paths))
    try PersistenceDurability.syncDirectory(root(paths))
  }
}
