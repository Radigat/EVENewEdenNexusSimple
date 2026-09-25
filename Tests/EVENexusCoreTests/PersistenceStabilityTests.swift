import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Persistence stability")
struct PersistenceStabilityTests {
  @Test
  func existingLegacyStoreIsMigrationSourceButCanonicalRemainsDestination() {
    let root = URL(fileURLWithPath: "/tmp/fixture-support", isDirectory: true)
    let legacy = root.appendingPathComponent("default.store")
    let paths = AppDataPaths.resolve(
      applicationSupportRoot: root,
      fileExists: { $0 == legacy.path }
    )

    #expect(paths.swiftDataStoreURL != legacy)
    #expect(paths.legacySwiftDataStoreURL == legacy)
    #expect(paths.swiftDataStoreLocation == .canonical)
  }

  @Test
  func canonicalStoreWinsWhenBothLocationsExist() {
    let root = URL(fileURLWithPath: "/tmp/fixture-support", isDirectory: true)
    let canonical =
      root
      .appendingPathComponent(AppDataPaths.applicationIdentifier)
      .appendingPathComponent("ApplicationData")
      .appendingPathComponent("EVENexusSimple.store")
    let legacy = root.appendingPathComponent("default.store")
    let paths = AppDataPaths.resolve(
      applicationSupportRoot: root,
      fileExists: { $0 == canonical.path || $0 == legacy.path }
    )

    #expect(paths.swiftDataStoreURL == canonical)
    #expect(paths.legacySwiftDataStoreURL == legacy)
    #expect(paths.swiftDataStoreLocation == .canonical)
  }

  @Test
  func legacyStoreIsCopiedWithoutChangingSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let legacy = root.appendingPathComponent("default.store")
    let source = Data("legacy-store".utf8)
    try source.write(to: legacy)
    let paths = AppDataPaths.resolve(
      applicationSupportRoot: root,
      fileExists: FileManager.default.fileExists(atPath:)
    )

    #expect(
      try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths)
    )
    #expect(try Data(contentsOf: legacy) == source)
    #expect(try Data(contentsOf: paths.swiftDataStoreURL) == source)
    #expect(
      try !PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths)
    )
  }

  @Test
  func unavailableRefreshRetainsPreviousValueAsStale() {
    let oldSource = SourceIdentity(
      provider: "ESI",
      version: "fixture-old",
      capturedAt: Date(timeIntervalSince1970: 10),
      snapshotID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
    let latestSource = SourceIdentity(
      provider: "ESI",
      version: "fixture-new",
      capturedAt: Date(timeIntervalSince1970: 20),
      snapshotID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
    let previous = Sourced(
      state: .fresh,
      value: [Int64(34): 100],
      source: oldSource
    )
    let failed = Sourced<[Int64: Int]>(
      state: .unavailable,
      value: nil,
      source: latestSource,
      diagnostics: ["fixture-offline"]
    )

    let retained = failed.retainingLastKnownValue(from: previous)

    #expect(retained.state == .stale)
    #expect(retained.value == [Int64(34): 100])
    #expect(retained.source == oldSource)
    #expect(retained.diagnostics.contains("latest-refresh-state:unavailable"))
  }

  @Test
  func successfulEmptyRefreshReplacesPreviousValue() {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let previous = Sourced(state: .fresh, value: [1, 2], source: source)
    let latest = Sourced(state: .fresh, value: [Int](), source: source)

    let retained = latest.retainingLastKnownValue(from: previous)

    #expect(retained.state == .fresh)
    #expect(retained.value == [])
  }

  @Test
  func repeatedFailuresKeepDiagnosticsBounded() {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    var retained = Sourced(
      state: .fresh,
      value: [1],
      source: source,
      diagnostics: (0..<32).map { "old-\($0)" }
    )
    for attempt in 0..<100 {
      retained = Sourced<[Int]>(
        state: .unavailable,
        value: nil,
        source: source,
        diagnostics: ["failure-\(attempt)"]
      ).retainingLastKnownValue(from: retained)
    }

    #expect(retained.value == [1])
    #expect(retained.state == .stale)
    #expect(retained.diagnostics.count <= 32)
  }

  @Test
  func schemaBackupIsCreatedOnceWithoutChangingTheSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let paths = AppDataPaths.resolve(
      applicationSupportRoot: root,
      fileExists: { _ in false }
    )
    try paths.prepareDirectories()
    var database: OpaquePointer?
    #expect(sqlite3_open(paths.swiftDataStoreURL.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE fixture (value INTEGER); INSERT INTO fixture VALUES (42);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let source = try Data(contentsOf: paths.swiftDataStoreURL)

    let first = try PersistenceSafetyBackup.createIfNeeded(
      paths: paths,
      schemaVersion: 1,
      now: Date(timeIntervalSince1970: 100),
      operationID: UUID(
        uuidString: "00000000-0000-0000-0000-000000000003"
      )!
    )
    let second = try PersistenceSafetyBackup.createIfNeeded(
      paths: paths,
      schemaVersion: 1,
      now: Date(timeIntervalSince1970: 200)
    )

    #expect(first != nil)
    #expect(second == nil)
    #expect(try Data(contentsOf: paths.swiftDataStoreURL) == source)
    var saved: OpaquePointer?
    let copy = first!.appendingPathComponent(paths.swiftDataStoreURL.lastPathComponent)
    #expect(sqlite3_open_v2(copy.path, &saved, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(saved) }
    var query: OpaquePointer?
    #expect(sqlite3_prepare_v2(saved, "SELECT value FROM fixture", -1, &query, nil) == SQLITE_OK)
    defer { sqlite3_finalize(query) }
    #expect(sqlite3_step(query) == SQLITE_ROW)
    #expect(sqlite3_column_int(query, 0) == 42)
  }
}
