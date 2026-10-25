import CSQLite
import EVEStaticDataKit
import Foundation
import Testing

@testable import EVENexusCore

/// Opt-in comparison of the old and new static-data paths on a real public
/// SDE package. It imports the package into an isolated temporary store and
/// sends no network requests. Durations come from a Debug test build, so the
/// ratios matter, not the absolute values; there are no time assertions.
@Suite("Static catalog benchmark")
struct StaticCatalogBenchmarkTests {
  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "EVE_STATIC_DATA_KIT_REAL_PACKAGE"
      ] != nil
        && ProcessInfo.processInfo.environment["EVE_NEXUS_RUN_BENCHMARKS"]
          == "1",
      "Set EVE_STATIC_DATA_KIT_REAL_PACKAGE and EVE_NEXUS_RUN_BENCHMARKS=1."
    )
  )
  func comparesOldAndNewStaticDataPathsOnTheRealSDE() async throws {
    let packageURL = URL(
      fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["EVE_STATIC_DATA_KIT_REAL_PACKAGE"]
      ),
      isDirectory: true
    )
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-benchmark-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("catalog-store", isDirectory: true)
    let activation = try await SQLiteStaticCatalog(rootURL: root)
      .activateStreaming(
        packageURL: packageURL,
        mapper: JSONLinesSDECatalogMapper(),
        batchSize: 500
      )
    let packagesURL = base.appendingPathComponent("packages", isDirectory: true)
    try FileManager.default.createDirectory(
      at: packagesURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: packagesURL.appendingPathComponent("real.evesde"),
      withDestinationURL: packageURL
    )
    let catalogURL = root.appendingPathComponent("catalogs", isDirectory: true)
      .appendingPathComponent(
        "sde-\(activation.buildNumber)-\(activation.contentSHA256.prefix(12))-catalog-v7.sqlite"
      )

    // New paths on the adapter-6 catalog.
    let dogmaFromTable = try await median {
      _ = try await SQLiteStaticCatalog(rootURL: root)
        .industryFacilityReferences()
    }
    let definitionsCold = try await median {
      _ = try await SQLiteStaticCatalog(rootURL: root)
        .manufacturingDefinitions()
    }
    let warmCatalog = SQLiteStaticCatalog(rootURL: root)
    let manufacturing = try await warmCatalog.manufacturingDefinitions()
    let reactions = try await warmCatalog.reactionDefinitions()
    let definitionsWarm = try await median {
      _ = try await warmCatalog.manufacturingDefinitions()
    }
    let scanTypeIDs = Set(
      (manufacturing + reactions).flatMap {
        [$0.productTypeID]
          + $0.activity.materials.map(\.typeID)
          + $0.activity.products.map(\.typeID)
      }
    )
    let sdeVolumes = try await warmCatalog.packagedVolumes(typeIDs: scanTypeIDs)

    // Old paths: no `type_dogma` table and no blueprint lookup indexes, as
    // in an adapter-5 catalog.
    try execute(
      """
      DROP INDEX idx_product_blueprint;
      DROP INDEX idx_skill_blueprint;
      DROP TABLE type_dogma;
      """,
      at: catalogURL
    )
    let dogmaFromPackage = try await median {
      _ = try await SQLiteStaticCatalog(rootURL: root)
        .industryFacilityReferences()
    }
    let productTypeIDs = manufacturing.map(\.productTypeID)
    let definitionsPerProduct = try await median(runs: 1) {
      let catalog = SQLiteStaticCatalog(rootURL: root)
      for productTypeID in productTypeIDs {
        _ = try await catalog.productionDefinition(productTypeID: productTypeID)
      }
    }

    #expect(!manufacturing.isEmpty)
    #expect(sdeVolumes.count <= scanTypeIDs.count)
    print(
      "benchmark build=\(activation.buildNumber)"
        + " facility-dogma table=\(dogmaFromTable) package=\(dogmaFromPackage)"
    )
    print(
      "benchmark manufacturing-definitions products=\(productTypeIDs.count)"
        + " set-based-cold=\(definitionsCold) set-based-warm=\(definitionsWarm)"
        + " per-product-without-indexes=\(definitionsPerProduct)"
    )
    print(
      "benchmark main-hub-scan-volume-requests types=\(scanTypeIDs.count)"
        + " old-esi=\(scanTypeIDs.count)"
        + " new-esi=\(scanTypeIDs.count - sdeVolumes.count)"
    )
  }

  /// Median of `runs` measurements after one unmeasured warm-up.
  private func median(
    runs: Int = 3,
    _ body: () async throws -> Void
  ) async throws -> String {
    try await body()
    var durations: [Duration] = []
    for _ in 0..<runs {
      let started = ContinuousClock.now
      try await body()
      durations.append(ContinuousClock.now - started)
    }
    return PerformanceLog.milliseconds(durations.sorted()[durations.count / 2])
  }

  private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      sqlite3_close(database)
      throw StaticCatalogError.database("benchmark-open")
    }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw StaticCatalogError.database("benchmark-execute")
    }
  }
}
