import Foundation
import Testing

@testable import EVENexusCore

@Suite("Persistence stability")
struct PersistenceStabilityTests {
  @Test
  func existingLegacyStoreWinsOverEmptyCanonicalLocation() {
    let root = URL(fileURLWithPath: "/tmp/fixture-support", isDirectory: true)
    let legacy = root.appendingPathComponent("default.store")
    let paths = AppDataPaths.resolve(
      applicationSupportRoot: root,
      fileExists: { $0 == legacy.path }
    )

    #expect(paths.swiftDataStoreURL == legacy)
    #expect(paths.swiftDataStoreLocation == .legacyDefaultStore)
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
    #expect(paths.swiftDataStoreLocation == .canonical)
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
    let source = Data("fixture-store".utf8)
    try source.write(to: paths.swiftDataStoreURL)

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
    #expect(
      try Data(
        contentsOf: first!.appendingPathComponent(
          paths.swiftDataStoreURL.lastPathComponent
        )
      ) == source
    )
  }
}
