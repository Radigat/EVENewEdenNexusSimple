import CSQLite
import Foundation
import Testing
@testable import EVENexusCore

@Suite("Full-store recovery")
struct StoreFullRestoreTests {
  private func fixture() throws -> AppDataPaths {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID())/support")
    let paths = AppDataPaths.resolve(applicationSupportRoot: support, fileExists: { _ in false })
    try paths.prepareDirectories()
    return paths
  }
  private func create(_ url: URL, value: Int) throws {
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "CREATE TABLE fixture(value INTEGER); INSERT INTO fixture VALUES(\(value));", nil, nil, nil) == SQLITE_OK)
  }
  private func validate(_ url: URL) throws -> [String: Int] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw POSIXError(.EIO) }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT value FROM fixture", -1, &statement, nil) == SQLITE_OK else { throw POSIXError(.EIO) }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw POSIXError(.EIO) }
    return ["fixture": Int(sqlite3_column_int(statement, 0))]
  }
  @Test func walOnlyRowsPublishedWithoutCompanions() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    var db: OpaquePointer?
    #expect(sqlite3_open(paths.legacySwiftDataStoreURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE fixture(value INTEGER); INSERT INTO fixture VALUES(72);", nil, nil, nil) == SQLITE_OK)
    #expect(FileManager.default.fileExists(atPath: paths.legacySwiftDataStoreURL.path + "-wal"))
    let legacyMain = try Data(contentsOf: paths.legacySwiftDataStoreURL)
    let legacyWAL = try Data(contentsOf: URL(fileURLWithPath: paths.legacySwiftDataStoreURL.path + "-wal"))
    #expect(try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths))
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 72])
    #expect(try Data(contentsOf: paths.legacySwiftDataStoreURL) == legacyMain)
    #expect(try Data(contentsOf: URL(fileURLWithPath: paths.legacySwiftDataStoreURL.path + "-wal")) == legacyWAL)
    #expect(!FileManager.default.fileExists(atPath: paths.swiftDataStoreURL.path + "-wal"))
    #expect(try !PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths))
  }
  @Test func failedPreparationRetriesAndCompanionsBlockPublication() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try Data("invalid".utf8).write(to: paths.legacySwiftDataStoreURL)
    #expect(throws: (any Error).self) { try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths) }
    #expect(!FileManager.default.fileExists(atPath: paths.swiftDataStoreURL.path))
    try FileManager.default.removeItem(at: paths.legacySwiftDataStoreURL)
    try create(paths.legacySwiftDataStoreURL, value: 7)
    let orphan = URL(fileURLWithPath: paths.swiftDataStoreURL.path + "-wal")
    try Data("orphan".utf8).write(to: orphan)
    #expect(throws: PersistenceStoreSeederError.destinationAlreadyExists) { try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths) }
    try FileManager.default.removeItem(at: orphan)
    #expect(try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths))
  }
  @Test(arguments: ["journal", "import", "original", "installed"])
  func interruptedTransactionsRollBack(boundary: String) throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try create(paths.swiftDataStoreURL, value: 99)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    let pending = paths.dataRoot.appendingPathComponent("recovery-import")
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    try Data("pending".utf8).write(to: pending.appendingPathComponent("current.store"))
    try StoreFullRestore.schedule(paths: paths)
    let preview = try StoreFullRestore.prepare(paths: paths, validate: validate)
    #expect(throws: (any Error).self) {
      try StoreFullRestore.activate(preview, paths: paths, validate: validate) {
        if $0 == boundary { throw POSIXError(.EINTR) }
      }
    }
    try StoreFullRestore.recoverInterrupted(paths: paths)
    try StoreFullRestore.recoverInterrupted(paths: paths)
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 99])
    #expect(FileManager.default.fileExists(atPath: pending.appendingPathComponent("current.store").path))
  }
  @Test func committedNeverRollsBackAndQuarantinesImport() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try create(paths.swiftDataStoreURL, value: 99)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    let pending = paths.dataRoot.appendingPathComponent("recovery-import")
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    try StoreFullRestore.schedule(paths: paths)
    let preview = try StoreFullRestore.prepare(paths: paths, validate: validate)
    #expect(throws: (any Error).self) {
      try StoreFullRestore.activate(preview, paths: paths, validate: validate) { if $0 == "committed" { throw POSIXError(.EINTR) } }
    }
    try StoreFullRestore.recoverInterrupted(paths: paths)
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 21])
    #expect(!StoreFullRestore.isPending(paths: paths))
    #expect(!FileManager.default.fileExists(atPath: pending.path))
    #expect(FileManager.default.fileExists(atPath: preview.backupDirectory.appendingPathComponent("original").path))
  }
  @Test func corruptCurrentRawBackupAndInvalidCandidateRefusal() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    let corrupt = Data("corrupted current".utf8)
    try corrupt.write(to: paths.swiftDataStoreURL)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    try StoreFullRestore.schedule(paths: paths)
    #expect(throws: (any Error).self) {
      try StoreFullRestore.prepare(paths: paths) { _ in throw POSIXError(.EINVAL) }
    }
    #expect(try Data(contentsOf: paths.swiftDataStoreURL) == corrupt)
    let preview = try StoreFullRestore.prepare(paths: paths, validate: validate)
    #expect(!preview.currentSnapshotAvailable)
    #expect(try Data(contentsOf: preview.backupDirectory.appendingPathComponent("current-raw/EVENexusSimple.store")) == corrupt)
    try StoreFullRestore.activate(preview, paths: paths, validate: validate)
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 21])
  }
  @Test func ambiguousOriginalStopsRecoveryAndPreservesCopies() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try create(paths.swiftDataStoreURL, value: 99)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    try StoreFullRestore.schedule(paths: paths)
    let preview = try StoreFullRestore.prepare(paths: paths, validate: validate)
    #expect(throws: (any Error).self) {
      try StoreFullRestore.activate(preview, paths: paths, validate: validate) { if $0 == "journal" { throw POSIXError(.EINTR) } }
    }
    let unexpected = paths.swiftDataStoreURL.deletingLastPathComponent().appendingPathComponent("unexpected")
    try Data("unrelated change".utf8).write(to: unexpected)
    #expect(throws: (any Error).self) { try StoreFullRestore.recoverInterrupted(paths: paths) }
    #expect(FileManager.default.fileExists(atPath: unexpected.path))
    #expect(FileManager.default.fileExists(atPath: paths.dataRoot.appendingPathComponent("full-restore/journal.json").path))
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 99])
  }
  @Test func invalidInstalledCandidateRollsBackAndRequiredBackupFailureStopsPreparation() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try create(paths.swiftDataStoreURL, value: 99)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    try StoreFullRestore.schedule(paths: paths)
    let preview = try StoreFullRestore.prepare(paths: paths, validate: validate)
    #expect(throws: (any Error).self) {
      try StoreFullRestore.activate(preview, paths: paths) { _ in throw POSIXError(.EIO) }
    }
    try StoreFullRestore.recoverInterrupted(paths: paths)
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 99])
    // A non-regular legacy companion cannot silently produce an incomplete raw backup.
    let support = URL(fileURLWithPath: paths.legacySwiftDataStoreURL.path + "_SUPPORT")
    try FileManager.default.createSymbolicLink(at: support, withDestinationURL: paths.swiftDataStoreURL)
    #expect(throws: (any Error).self) { try StoreFullRestore.prepare(paths: paths, validate: validate) }
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 99])
  }
  @Test func validatorChildRetainsLockAfterParentOwnerIsReleased() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    var parentLock: PersistenceProcessLock? = try PersistenceProcessLock(paths: paths)
    let inherited = try #require(parentLock).duplicateForChild()
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    child.standardInput = inherited
    try child.run()
    try inherited.close()
    parentLock = nil
    #expect(child.isRunning)
    #expect(throws: (any Error).self) { try PersistenceProcessLock(paths: paths) }
    child.terminate()
    child.waitUntilExit()
    let replacement = try PersistenceProcessLock(paths: paths)
    withExtendedLifetime(replacement) {}
  }
  @Test func cancelPreservesCurrentAndLockExcludesCompetitors() throws {
    let paths = try fixture()
    defer { try? FileManager.default.removeItem(at: paths.applicationSupportRoot.deletingLastPathComponent()) }
    try create(paths.swiftDataStoreURL, value: 99)
    try create(paths.legacySwiftDataStoreURL, value: 21)
    let lock = try PersistenceProcessLock(paths: paths)
    withExtendedLifetime(lock) {
      #expect(throws: (any Error).self) { try PersistenceProcessLock(paths: paths) }
    }
    try StoreFullRestore.schedule(paths: paths)
    try StoreFullRestore.cancel(paths: paths)
    #expect(!StoreFullRestore.isPending(paths: paths))
    #expect(try validate(paths.swiftDataStoreURL) == ["fixture": 99])
  }
}
