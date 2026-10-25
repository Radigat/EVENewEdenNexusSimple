import CSQLite
import EVEStaticDataKit
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Build-specific SQLite SDE catalog")
struct SQLiteStaticCatalogTests {
  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "EVE_STATIC_DATA_KIT_REAL_PACKAGE"
      ] != nil,
      "Set EVE_STATIC_DATA_KIT_REAL_PACKAGE to a prepared public SDE package."
    )
  )
  func validatesAndActivatesOptInCurrentRealSDEInAnIsolatedSQLiteStore()
    async throws
  {
    guard
      let packagePath = ProcessInfo.processInfo.environment[
        "EVE_STATIC_DATA_KIT_REAL_PACKAGE"
      ]
    else {
      Issue.record("The opt-in real SDE package path is missing.")
      return
    }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-live-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("catalog-store", isDirectory: true)

    let catalog = SQLiteStaticCatalog(rootURL: root)
    let mapper = JSONLinesSDECatalogMapper()
    let packageURL = URL(
      fileURLWithPath: packagePath,
      isDirectory: true
    )
    let result = try await catalog.validateStreamingInIsolatedStore(
      packageURL: packageURL,
      mapper: mapper,
      batchSize: 500,
      operationID: UUID()
    )

    #expect(result.reopenedSuccessfully)
    #expect(result.buildNumber > 0)
    #expect(result.counts.itemTypes > 0)
    #expect(result.counts.blueprints > 0)

    let activation = try await catalog.activateStreaming(
      packageURL: packageURL,
      mapper: mapper,
      batchSize: 500
    )
    let active = try #require(try await catalog.activeSDEVersion())
    #expect(active.buildNumber == result.buildNumber)
    #expect(activation.buildNumber == result.buildNumber)
    #expect(activation.counts == result.counts)

    // Set-based complete definitions equal the per-product lookups.
    for definition in try await catalog.manufacturingDefinitions()
      + catalog.reactionDefinitions()
    {
      let expected = try #require(
        try await catalog.productionDefinition(
          productTypeID: definition.productTypeID
        )
      )
      guard expected.activity.kind == definition.activity.kind else {
        continue
      }
      #expect(definition.blueprintTypeID == expected.blueprintTypeID)
      #expect(definition.maxProductionLimit == expected.maxProductionLimit)
      #expect(definition.activity == expected.activity)
    }

    // Adapter 6 reads facility dogma from the catalog. Without the table the
    // same package's typeDogma file must yield the identical reference.
    let fromCatalog = try await catalog.industryFacilityReferences()
    #expect(fromCatalog.structures.contains { $0.typeID == 35_825 })
    #expect(!fromCatalog.rigs.isEmpty)
    #expect(!fromCatalog.serviceModules.isEmpty)
    let packagesURL = base.appendingPathComponent("packages", isDirectory: true)
    try FileManager.default.createDirectory(
      at: packagesURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: packagesURL.appendingPathComponent("real.evesde"),
      withDestinationURL: packageURL
    )
    let activeFileName =
      "sde-\(active.buildNumber)-\(active.contentSHA256.prefix(12))-catalog-v7.sqlite"
    try dropTable(
      "type_dogma",
      at: root.appendingPathComponent("catalogs", isDirectory: true)
        .appendingPathComponent(activeFileName)
    )
    let fromPackage = try await SQLiteStaticCatalog(rootURL: root)
      .industryFacilityReferences()
    #expect(try withoutSources(fromCatalog) == withoutSources(fromPackage))
  }

  /// JSON form without `source` identities, whose capture time differs per
  /// call.
  private func withoutSources(_ value: some Encodable) throws -> NSObject {
    func strip(_ value: Any) -> Any {
      if let dictionary = value as? [String: Any] {
        return dictionary.filter { $0.key != "source" }.mapValues(strip)
      }
      if let array = value as? [Any] {
        return array.map(strip)
      }
      return value
    }
    let object = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(value)
    )
    return try #require(strip(object) as? NSObject)
  }

  @Test
  func activatesBacksUpQueriesAndRollsBack() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)

    let first = try fixture(build: 1, productName: "Fixture Ship")
    _ = try await catalog.activate(first)
    #expect(try await catalog.typeID(named: "fixture ship") == 1)
    #expect(
      try await catalog.typeNames(ids: [1, 2, 999])
        == [1: "Fixture Ship", 2: "Fixture Mineral"]
    )
    #expect(
      try await catalog.searchItemTypes(matching: "min")
        == [ItemTypeSearchResult(id: 2, name: "Fixture Mineral")]
    )
    #expect(
      try await catalog.searchItemTypes(matching: "fixt", limit: 2)
        .map(\.name) == ["Fixture Ship", "Fixture Mineral"]
    )
    #expect(try await catalog.searchItemTypes(matching: "fi").isEmpty)
    #expect(
      try await catalog.searchItemTypes(matching: "unpublished").isEmpty
    )
    #expect(
      try await catalog.searchManufacturingProducts(matching: "fixture")
        == [
          ManufacturingProductSearchResult(
            id: 1,
            name: "Fixture Ship",
            outputPerRun: 1,
            blueprintTypeID: 100,
            categoryName: "Fixture",
            groupName: "Fixture Group",
            metaGroupID: 2,
            techLevel: 2
          )
        ]
    )
    #expect(
      try await catalog.searchManufacturingProducts(matching: "min").isEmpty
    )
    #expect(
      try await catalog.searchManufacturingProducts(matching: "fi").isEmpty
    )
    let contractMetadata = try await catalog.publicContractItemMetadata(
      typeIDs: [1, 2, 99, 999]
    )
    #expect(contractMetadata[1]?.typeName == "Fixture Ship")
    #expect(contractMetadata[1]?.groupName == "Fixture Group")
    #expect(contractMetadata[1]?.categoryName == "Fixture")
    #expect(contractMetadata[99] == nil)
    #expect(
      try await catalog.productionDefinition(productTypeID: 1)?
        .blueprintTypeID == 100
    )
    #expect(
      try await catalog.productionDefinition(productTypeID: 1)?
        .activity.materials.first?.quantity == 7
    )
    let research = try #require(
      try await catalog.blueprintResearchDefinition(blueprintTypeID: 100)
    )
    #expect(research.blueprintName == "Fixture Blueprint")
    #expect(research.basePrice == 1_000)
    #expect(research.materialResearchTimeSeconds == 105)
    #expect(research.timeResearchTimeSeconds == 105)
    #expect(research.manufacturingMaterials.first?.quantity == 7)
    #expect(!research.hasUnresolvedReferences)
    let scienceActivities = try await catalog.blueprintScienceActivities(
      blueprintTypeID: 100
    )
    let materialResearch = try #require(
      scienceActivities.first { $0.kind == .materialResearch }
    )
    #expect(
      materialResearch.requiredSkills
        == [BlueprintSkillRequirement(typeID: 2, level: 4)]
    )
    let classification = try #require(
      try await catalog.industryClassification(productTypeID: 1)
    )
    #expect(classification.manufacturingCategory == .module)
    #expect(classification.metaGroupID == 2)
    #expect(classification.techLevel == 2)
    #expect(try await catalog.packagedVolume(typeID: 1) == 1)
    #expect(
      try await catalog.scienceSkills().map(\.name)
        == ["Fixture Encryption Methods"]
    )
    #expect(try await catalog.createSafetyBackup(operationID: UUID()))

    let second = try fixture(build: 2, productName: "Renamed Ship")
    _ = try await catalog.activate(second)
    #expect(try await catalog.typeID(named: "Renamed Ship") == 1)

    _ = try await catalog.rollback(toBuildNumber: 1)
    #expect(try await catalog.typeID(named: "Fixture Ship") == 1)
    #expect(try await catalog.activeSDEVersion()?.buildNumber == 1)
  }

  @Test
  func assembledVolumeNeverFallsBackAsPackagedTransportVolume() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-packaged-volume-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(
      build: 7,
      productName: "Assembled Ship",
      productPackagedVolume: nil
    )

    _ = try await catalog.activate(snapshot)

    #expect(try await catalog.packagedVolume(typeID: 1) == nil)
    #expect(try await catalog.packagedVolumes(typeIDs: [1]).isEmpty)
  }

  @Test
  func returnsCompressedOreWithAuthoritativeOutputsAndSkill() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-compressed-ore-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(
      build: 8,
      productName: "Fixture Ship",
      includeCompressedOre: true
    )
    _ = try await catalog.activate(snapshot)

    let option = try #require(
      try await catalog.compressedOreOptions(producing: [2]).first
    )

    #expect(option.typeID == 500)
    #expect(option.name == "Compressed Fixture Ore")
    #expect(option.packagedVolume == 0.15)
    #expect(option.reprocessingSkillTypeID == 12_104)
    #expect(option.kind == .asteroidOre)
    #expect(
      option.outputs
        == [ReprocessingMaterialOutput(typeID: 2, quantity: 415)]
    )
  }

  @Test
  func streamsBatchesIntoIsolatedStoreAndActivation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-streaming-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(build: 3, productName: "Streamed Ship")
    let mapper = FixtureStreamingMapper(snapshot: snapshot)
    let packageURL = root.appendingPathComponent("fixture-package")
    let operationID = UUID()

    let staging = try await catalog.validateStreamingInIsolatedStore(
      packageURL: packageURL,
      mapper: mapper,
      batchSize: 2,
      operationID: operationID
    )
    #expect(staging.reopenedSuccessfully)
    #expect(staging.counts.itemTypes == 9)

    let activation = try await catalog.activateStreaming(
      packageURL: packageURL,
      mapper: mapper,
      batchSize: 2
    )
    #expect(activation.buildNumber == 3)
    #expect(try await catalog.typeID(named: "Streamed Ship") == 1)
    #expect(
      try await catalog.reactionRuleProfile()?.catalogBuildNumber == 3
    )
    try await catalog.cleanup(operationID: operationID)
  }

  @Test
  func sameBuildReimportRebuildsCurrentAdapterAndRetainsLegacyCatalog()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-same-build-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try fixture(build: 6, productName: "Reimported Ship")
    let initialCatalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await initialCatalog.activate(snapshot)

    let hashPrefix = snapshot.contentSHA256.prefix(12)
    let currentName =
      "sde-\(snapshot.buildNumber)-\(hashPrefix)-catalog-v7.sqlite"
    let legacyName =
      "sde-\(snapshot.buildNumber)-\(hashPrefix).sqlite"
    let catalogsURL = root.appendingPathComponent(
      "catalogs",
      isDirectory: true
    )
    let currentURL = catalogsURL.appendingPathComponent(currentName)
    let legacyURL = catalogsURL.appendingPathComponent(legacyName)
    try FileManager.default.copyItem(at: currentURL, to: legacyURL)
    try FileManager.default.removeItem(at: currentURL)
    let legacyPointer =
      """
      {
        "buildNumber": \(snapshot.buildNumber),
        "contentSHA256": "\(snapshot.contentSHA256)",
        "fileName": "\(legacyName)"
      }
      """
    try Data(legacyPointer.utf8).write(
      to: root.appendingPathComponent("active-sde.json"),
      options: .atomic
    )

    let reimportingCatalog = SQLiteStaticCatalog(rootURL: root)
    #expect(
      try await reimportingCatalog.activeSDEVersion()?.buildNumber
        == snapshot.buildNumber
    )
    #expect(
      try await reimportingCatalog.createSafetyBackup(operationID: UUID())
    )
    let activation = try await reimportingCatalog.activateStreaming(
      packageURL: root.appendingPathComponent("fixture-package"),
      mapper: FixtureStreamingMapper(snapshot: snapshot),
      batchSize: 2
    )

    #expect(!activation.reusedExistingVersion)
    #expect(FileManager.default.fileExists(atPath: legacyURL.path))
    #expect(FileManager.default.fileExists(atPath: currentURL.path))
    #expect(try await reimportingCatalog.typeID(named: "Reimported Ship") == 1)
    let activePointer = try String(
      contentsOf: root.appendingPathComponent("active-sde.json"),
      encoding: .utf8
    )
    #expect(activePointer.contains(currentName))

    _ = try await reimportingCatalog.rollback(
      toBuildNumber: snapshot.buildNumber
    )
    let rolledBackPointer = try String(
      contentsOf: root.appendingPathComponent("active-sde.json"),
      encoding: .utf8
    )
    #expect(rolledBackPointer.contains(legacyName))
    #expect(FileManager.default.fileExists(atPath: currentURL.path))
  }

  @Test
  func previousVersionedAdapterPointerRemainsReadableForSafeReimport()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-previous-adapter-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try fixture(build: 7, productName: "Previous Adapter Ship")
    let currentCatalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await currentCatalog.activate(snapshot)

    let hashPrefix = snapshot.contentSHA256.prefix(12)
    let currentName =
      "sde-\(snapshot.buildNumber)-\(hashPrefix)-catalog-v7.sqlite"
    let previousName =
      "sde-\(snapshot.buildNumber)-\(hashPrefix)-catalog-v5.sqlite"
    let catalogsURL = root.appendingPathComponent(
      "catalogs",
      isDirectory: true
    )
    try FileManager.default.moveItem(
      at: catalogsURL.appendingPathComponent(currentName),
      to: catalogsURL.appendingPathComponent(previousName)
    )
    let previousPointer =
      """
      {
        "buildNumber": \(snapshot.buildNumber),
        "contentSHA256": "\(snapshot.contentSHA256)",
        "fileName": "\(previousName)"
      }
      """
    try Data(previousPointer.utf8).write(
      to: root.appendingPathComponent("active-sde.json"),
      options: .atomic
    )

    let upgradedCatalog = SQLiteStaticCatalog(rootURL: root)
    let active = try await upgradedCatalog.activeSDEVersion()

    #expect(active?.buildNumber == snapshot.buildNumber)
    #expect(active?.contentSHA256 == snapshot.contentSHA256)
  }

  @Test
  func returnsEveryCompletePublishedReactionDefinition() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-reactions-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(
      build: 4,
      productName: "Fixture Ship",
      includeReaction: true
    )
    _ = try await catalog.activate(snapshot)

    let definitions = try await catalog.reactionDefinitions()

    #expect(definitions.count == 1)
    #expect(definitions.first?.blueprintTypeID == 101)
    #expect(definitions.first?.productTypeID == 3)
    #expect(definitions.first?.activity.kind == .reaction)
    #expect(definitions.first?.activity.materials.first?.typeID == 4)
    #expect(definitions.first?.source.version == "4")
  }

  @Test
  func rejectsTamperedActivePointerPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-pointer-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let pointer =
      """
      {
        "buildNumber": 1,
        "contentSHA256": "\(String(repeating: "a", count: 64))",
        "fileName": "../outside.sqlite"
      }
      """
    try Data(pointer.utf8).write(
      to: root.appendingPathComponent("active-sde.json")
    )
    let catalog = SQLiteStaticCatalog(rootURL: root)

    await #expect(throws: StaticCatalogError.invalidPointer) {
      _ = try await catalog.activeSDEVersion()
    }
  }

  @Test
  func readsFacilityAndRigRulesFromTheCatalogWithoutThePackageFile()
    async throws
  {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-facility-catalog-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let snapshot = try withTypeDogma(
      try fixture(
        build: 3,
        productName: "Fixture Ship",
        includeReprocessingReference: true
      ),
      try facilityTypeDogma()
    )
    let snapshotCatalog = SQLiteStaticCatalog(
      rootURL: base.appendingPathComponent("snapshot", isDirectory: true)
        .appendingPathComponent("catalog-store", isDirectory: true)
    )
    _ = try await snapshotCatalog.activate(snapshot)
    let streamingCatalog = SQLiteStaticCatalog(
      rootURL: base.appendingPathComponent("streaming", isDirectory: true)
        .appendingPathComponent("catalog-store", isDirectory: true)
    )
    _ = try await streamingCatalog.activateStreaming(
      packageURL: base.appendingPathComponent("fixture-package"),
      mapper: FixtureStreamingMapper(snapshot: snapshot),
      batchSize: 2
    )

    // No typeDogma package file exists: adapter 6 reads only the catalog.
    for catalog in [snapshotCatalog, streamingCatalog] {
      try expectFacilityReference(
        try await catalog.industryFacilityReferences()
      )
    }
  }

  @Test
  func readsFacilityAndRigRulesFromThePackageWhenTheCatalogPredatesAdapterSix()
    async throws
  {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-facility-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent(
      "catalog-store",
      isDirectory: true
    )
    let snapshot = try fixture(
      build: 3,
      productName: "Fixture Ship",
      includeReprocessingReference: true
    )
    _ = try await SQLiteStaticCatalog(rootURL: root).activate(snapshot)
    try dropTable(
      "type_dogma",
      at: root.appendingPathComponent("catalogs", isDirectory: true)
        .appendingPathComponent(
          "sde-\(snapshot.buildNumber)-\(snapshot.contentSHA256.prefix(12))-catalog-v7.sqlite"
        )
    )
    try writeFacilityPackage(baseURL: base, snapshot: snapshot)

    let catalog = SQLiteStaticCatalog(rootURL: root)
    try expectFacilityReference(try await catalog.industryFacilityReferences())
  }

  private func expectFacilityReference(
    _ reference: IndustryFacilityReferenceSnapshot
  ) throws {
    let structure = try #require(
      reference.structures.first { $0.typeID == 35_825 }
    )
    let rig = try #require(
      reference.rigs.first { $0.typeID == 43_855 }
    )
    let inventionRig = try #require(
      reference.rigs.first { $0.typeID == 43_722 }
    )
    let researchLab = try #require(
      reference.serviceModules.first { $0.typeID == 35_891 }
    )
    let tatara = try #require(
      reference.structures.first { $0.typeID == 35_836 }
    )
    let reprocessingMonitor = try #require(
      reference.rigs.first { $0.typeID == 46_640 }
    )
    let reprocessingFacility = try #require(
      reference.serviceModules.first { $0.typeID == 35_899 }
    )
    #expect(structure.size == .medium)
    #expect(structure.rigSlots == 3)
    #expect(abs(structure.manufacturingMaterialBonusPercent - 1) < 0.000_001)
    #expect(abs(structure.manufacturingTimeBonusPercent - 15) < 0.000_001)
    #expect(structure.jobCostMultiplier == 0.97)
    #expect(rig.size == .medium)
    #expect(rig.manufacturingCategories == [.small])
    #expect(rig.materialBonusPercent == 2)
    #expect(rig.timeBonusPercent == 0)
    #expect(rig.lowSecurityMultiplier == 1.9)
    #expect(inventionRig.scienceActivities == [.invention])
    #expect(inventionRig.jobCostBonusPercent == 10)
    #expect(inventionRig.timeBonusPercent == 20)
    #expect(structure.groupID == 1_404)
    #expect(
      researchLab.activities
        == [.copying, .materialResearch, .timeResearch]
    )
    #expect(researchLab.compatibleStructureGroupIDs.contains(1_404))
    #expect(tatara.reprocessingEfficiencyBonusPercent == 5.5)
    #expect(reprocessingMonitor.size == .large)
    #expect(reprocessingMonitor.normalOreYieldMultiplier == 0.53)
    #expect(reprocessingMonitor.moonOreYieldMultiplier == 0.53)
    #expect(reprocessingMonitor.iceYieldMultiplier == 0.53)
    #expect(reprocessingFacility.normalOreYieldMultiplier == 0.5)
  }

  @Test
  func returnsPublishedMoonMaterialsFromTheirSDEGroup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-moon-materials-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(
      build: 5,
      productName: "Fixture Ship",
      includeMoonMaterials: true
    )
    _ = try await catalog.activate(snapshot)

    let moonMaterials = try await catalog.moonMaterials()

    #expect(
      moonMaterials.materials
        == [
          MoonMaterial(id: 16_634, name: "Atmospheric Gases"),
          MoonMaterial(id: 16_643, name: "Cadmium"),
        ]
    )
    #expect(moonMaterials.source.provider == "CCP SDE")
    #expect(moonMaterials.source.version == "5")
  }

  @Test
  func returnsPublishedStandardMineralsFromTheirSDEGroup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-minerals-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(
      build: 6,
      productName: "Fixture Ship",
      includeMinerals: true
    )
    _ = try await catalog.activate(snapshot)

    let minerals = try await catalog.minerals()

    #expect(
      minerals.materials
        == [
          MaterialPurchaseItem(id: 35, name: "Pyerite"),
          MaterialPurchaseItem(id: 34, name: "Tritanium"),
        ]
    )
    #expect(minerals.source.provider == "CCP SDE")
    #expect(minerals.source.version == "6")
  }

  @Test
  func mineralCatalogDoesNotFallBackWhenSDEGroupIsMissing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-missing-minerals-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await catalog.activate(
      fixture(build: 7, productName: "Fixture Ship")
    )

    await #expect(
      throws: StaticCatalogError.database("missing-minerals")
    ) {
      try await catalog.minerals()
    }
  }

  @Test
  func completeDefinitionsMatchPerProductLookupsInProductNameOrder()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-definitions-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await catalog.activate(try definitionFixture(build: 8))

    let definitions = try await catalog.manufacturingDefinitions()

    // Name order; the unresolved-material blueprint and the unpublished
    // blueprint stay excluded.
    #expect(definitions.map(\.productTypeID) == [601, 622, 1, 602, 600])
    for definition in definitions {
      let expected = try #require(
        try await catalog.productionDefinition(
          productTypeID: definition.productTypeID
        )
      )
      #expect(definition.blueprintTypeID == expected.blueprintTypeID)
      #expect(definition.maxProductionLimit == expected.maxProductionLimit)
      #expect(definition.activity == expected.activity)
      #expect(definition.source.provider == expected.source.provider)
      #expect(definition.source.version == expected.source.version)
    }
    let zeta = try #require(definitions.first { $0.productTypeID == 600 })
    #expect(zeta.activity.materials.map(\.typeID) == [620, 621, 622])
    #expect(zeta.activity.durationSeconds == 300)
    let charge = try #require(definitions.first { $0.productTypeID == 601 })
    #expect(charge.activity.products.map(\.typeID) == [601, 622])
    #expect(charge.activity.products.last?.probability == 0.5)
    #expect(charge.maxProductionLimit == nil)

    let reactions = try await catalog.reactionDefinitions()
    #expect(reactions.map(\.productTypeID) == [3])
    #expect(reactions.first?.activity.kind == .reaction)
  }

  @Test
  func completeDefinitionsAreReusedUntilTheActiveCatalogChanges()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-definition-cache-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await catalog.activate(
      try fixture(build: 8, productName: "First Ship")
    )

    let first = try await catalog.manufacturingDefinitions()
    let second = try await catalog.manufacturingDefinitions()
    #expect(
      first.map(\.source.snapshotID) == second.map(\.source.snapshotID)
    )

    _ = try await catalog.activate(
      try fixture(build: 9, productName: "Second Ship")
    )
    let replaced = try await catalog.manufacturingDefinitions()
    #expect(replaced.map(\.source.version) == ["9"])
    #expect(
      try await catalog.typeName(id: replaced[0].productTypeID)
        == "Second Ship"
    )
  }

  @Test
  func bothWritersCreateTheAdapterSixLookupIndexesAndDogmaTable()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-adapter-six-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try withTypeDogma(
      try fixture(
        build: 4,
        productName: "Indexed Ship",
        includeReprocessingReference: true
      ),
      try facilityTypeDogma()
    )
    let snapshotRoot = root.appendingPathComponent("snapshot")
    _ = try await SQLiteStaticCatalog(rootURL: snapshotRoot).activate(snapshot)
    let streamingRoot = root.appendingPathComponent("streaming")
    _ = try await SQLiteStaticCatalog(rootURL: streamingRoot)
      .activateStreaming(
        packageURL: root.appendingPathComponent("fixture-package"),
        mapper: FixtureStreamingMapper(snapshot: snapshot),
        batchSize: 2
      )

    let fileName =
      "sde-\(snapshot.buildNumber)-\(snapshot.contentSHA256.prefix(12))-catalog-v7.sqlite"
    for storeRoot in [snapshotRoot, streamingRoot] {
      let url = storeRoot.appendingPathComponent("catalogs")
        .appendingPathComponent(fileName)
      let indexes = try schemaNames(type: "index", at: url)
      #expect(indexes.contains("idx_product_blueprint"))
      #expect(indexes.contains("idx_skill_blueprint"))
      #expect(try schemaNames(type: "table", at: url).contains("type_dogma"))
      #expect(
        try scalarCount("SELECT COUNT(*) FROM type_dogma", at: url) == 7
      )
    }
  }

  @Test
  func bothWritersStoreTheMarketTreeAndItsSubtreeItems() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-market-groups-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try marketGroupFixture(build: 4)

    let snapshotCatalog = SQLiteStaticCatalog(
      rootURL: root.appendingPathComponent("snapshot", isDirectory: true)
    )
    _ = try await snapshotCatalog.activate(snapshot)
    let streamingCatalog = SQLiteStaticCatalog(
      rootURL: root.appendingPathComponent("streaming", isDirectory: true)
    )
    _ = try await streamingCatalog.activateStreaming(
      packageURL: root.appendingPathComponent("fixture-package"),
      mapper: FixtureStreamingMapper(snapshot: snapshot),
      batchSize: 2
    )

    for catalog in [snapshotCatalog, streamingCatalog] {
      let tree = try await catalog.marketGroups()
      #expect(tree.availability == .available)
      #expect(tree.source.version == "4")
      #expect(
        tree.groups.map(\.name)
          == ["Harvest Equipment", "Materials", "Mining Lasers", "Ship Equipment"]
      )
      let harvest = try #require(tree.groups.first { $0.id == 1_001 })
      #expect(harvest.parentID == 1_000)
      #expect(harvest.hasTypes)
      #expect(tree.groups.first { $0.id == 1_000 }?.parentID == nil)

      let equipment = try await catalog.tradeItems(inMarketGroupSubtree: 1_000)
      #expect(equipment.availability == .available)
      #expect(equipment.rootMarketGroupID == 1_000)
      // Published descendants only, ordered by name; the unpublished type in
      // the same leaf group is excluded and the sibling root is not included.
      #expect(equipment.items.map(\.id) == [100, 1])
      #expect(equipment.items.map(\.marketGroupID) == [1_001, 1_002])
      #expect(equipment.items.first?.packagedVolume == 1)
      // A missing packaged volume stays unknown instead of using the
      // assembled volume.
      #expect(equipment.items.last?.packagedVolume == nil)

      let leaf = try await catalog.tradeItems(inMarketGroupSubtree: 1_002)
      #expect(leaf.items.map(\.id) == [1])
      let materials = try await catalog.tradeItems(inMarketGroupSubtree: 2_000)
      #expect(materials.items.map(\.id) == [2])
      let unknown = try await catalog.tradeItems(inMarketGroupSubtree: 9_999)
      #expect(unknown.availability == .available)
      #expect(unknown.items.isEmpty)
    }
  }

  @Test
  func catalogWithoutMarketTreeReportsReimportInsteadOfFailing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-legacy-market-groups-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try marketGroupFixture(build: 5)
    _ = try await SQLiteStaticCatalog(rootURL: root).activate(snapshot)
    let fileName =
      "sde-\(snapshot.buildNumber)-\(snapshot.contentSHA256.prefix(12))-catalog-v7.sqlite"
    try dropMarketGroupTable(
      at: root.appendingPathComponent("catalogs", isDirectory: true)
        .appendingPathComponent(fileName)
    )

    let catalog = SQLiteStaticCatalog(rootURL: root)
    let tree = try await catalog.marketGroups()
    let items = try await catalog.tradeItems(inMarketGroupSubtree: 1_000)

    #expect(tree.availability == .requiresSDEReimport)
    #expect(tree.groups.isEmpty)
    #expect(items.availability == .requiresSDEReimport)
    #expect(items.items.isEmpty)
    #expect(try await catalog.typeID(named: "Market Ship") == 1)
  }

  @Test
  func duplicateMarketGroupsAreRejected() throws {
    let group = StaticMarketGroupSnapshot(
      externalID: 7,
      parentExternalID: nil,
      name: "Duplicate",
      hasTypes: true
    )
    #expect(
      throws: StaticDataCatalogValidationError.duplicateMarketGroupID(7)
    ) {
      _ = try withMarketGroups(
        try fixture(build: 9, productName: "Market Ship"),
        groups: [group, group],
        assignments: [:]
      )
    }
  }

  private func marketGroupFixture(build: Int) throws
    -> StaticDataCatalogSnapshot
  {
    try withMarketGroups(
      try fixture(
        build: build,
        productName: "Market Ship",
        productPackagedVolume: nil
      ),
      groups: [
        StaticMarketGroupSnapshot(
          externalID: 1_000,
          parentExternalID: nil,
          name: "Ship Equipment",
          hasTypes: false
        ),
        StaticMarketGroupSnapshot(
          externalID: 1_001,
          parentExternalID: 1_000,
          name: "Harvest Equipment",
          hasTypes: true
        ),
        StaticMarketGroupSnapshot(
          externalID: 1_002,
          parentExternalID: 1_001,
          name: "Mining Lasers",
          hasTypes: true
        ),
        StaticMarketGroupSnapshot(
          externalID: 2_000,
          parentExternalID: nil,
          name: "Materials",
          hasTypes: true
        ),
      ],
      assignments: [1: 1_002, 99: 1_002, 100: 1_001, 2: 2_000]
    )
  }

  @Test
  func resolvesExactEnglishAndGermanItemNames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-localized-names-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = try withGermanNames(
      try fixture(build: 9, productName: "Name Ship"),
      names: [1: "Namensschiff", 2: "Doppelt", 100: "Doppelt", 99: "Versteckt"]
    )
    let catalog = SQLiteStaticCatalog(rootURL: root)
    _ = try await catalog.activate(snapshot)

    let names = ["name ship", "Namensschiff", "Doppelt", "Versteckt", "Nichts", ""]
    let resolved = try await catalog.resolveItemTypeNames(names)
    #expect(resolved["name ship"] == .resolved(typeID: 1, name: "Name Ship", language: .english))
    #expect(
      resolved["Namensschiff"] == .resolved(typeID: 1, name: "Name Ship", language: .german)
    )
    #expect(resolved["Doppelt"] == .ambiguous([2, 100]))
    #expect(resolved["Versteckt"] == .unknown)
    #expect(resolved["Nichts"] == .unknown)
    #expect(resolved[""] == .unknown)

    // A catalog before adapter 7 has no German names: that state stays
    // explicit instead of reporting the name as unknown.
    let fileName =
      "sde-\(snapshot.buildNumber)-\(snapshot.contentSHA256.prefix(12))-catalog-v7.sqlite"
    try dropTable(
      "item_type_localized_names",
      at: root.appendingPathComponent("catalogs", isDirectory: true)
        .appendingPathComponent(fileName)
    )
    let legacy = try await SQLiteStaticCatalog(rootURL: root)
      .resolveItemTypeNames(["Name Ship", "Namensschiff"])
    #expect(legacy["Name Ship"] == .resolved(typeID: 1, name: "Name Ship", language: .english))
    #expect(legacy["Namensschiff"] == .localizedNamesUnavailable)
  }

  private func withGermanNames(
    _ base: StaticDataCatalogSnapshot,
    names: [Int64: String]
  ) throws -> StaticDataCatalogSnapshot {
    try StaticDataCatalogSnapshot(
      buildNumber: base.buildNumber,
      contentSHA256: base.contentSHA256,
      officialArchiveURL: base.officialArchiveURL,
      sourceFormat: base.sourceFormat,
      categories: base.categories,
      groups: base.groups,
      itemTypes: base.itemTypes.map { type in
        StaticItemTypeSnapshot(
          externalID: type.externalID,
          groupExternalID: type.groupExternalID,
          categoryExternalID: type.categoryExternalID,
          marketGroupExternalID: type.marketGroupExternalID,
          name: type.name,
          description: type.description,
          volume: type.volume,
          packagedVolume: type.packagedVolume,
          basePrice: type.basePrice,
          portionSize: type.portionSize,
          published: type.published,
          iconExternalID: type.iconExternalID,
          metaGroupExternalID: type.metaGroupExternalID,
          techLevel: type.techLevel,
          germanName: names[type.externalID]
        )
      },
      typeMaterials: base.typeMaterials,
      blueprints: base.blueprints,
      decryptors: base.decryptors,
      marketGroups: base.marketGroups,
      reactionRuleProfile: base.reactionRuleProfile,
      typeDogma: base.typeDogma
    )
  }

  private func withMarketGroups(
    _ base: StaticDataCatalogSnapshot,
    groups: [StaticMarketGroupSnapshot],
    assignments: [Int64: Int64]
  ) throws -> StaticDataCatalogSnapshot {
    try StaticDataCatalogSnapshot(
      buildNumber: base.buildNumber,
      contentSHA256: base.contentSHA256,
      officialArchiveURL: base.officialArchiveURL,
      sourceFormat: base.sourceFormat,
      categories: base.categories,
      groups: base.groups,
      itemTypes: base.itemTypes.map { type in
        StaticItemTypeSnapshot(
          externalID: type.externalID,
          groupExternalID: type.groupExternalID,
          categoryExternalID: type.categoryExternalID,
          marketGroupExternalID: assignments[type.externalID]
            ?? type.marketGroupExternalID,
          name: type.name,
          description: type.description,
          volume: type.volume,
          packagedVolume: type.packagedVolume,
          basePrice: type.basePrice,
          portionSize: type.portionSize,
          published: type.published,
          iconExternalID: type.iconExternalID,
          metaGroupExternalID: type.metaGroupExternalID,
          techLevel: type.techLevel
        )
      },
      typeMaterials: base.typeMaterials,
      blueprints: base.blueprints,
      decryptors: base.decryptors,
      marketGroups: groups,
      reactionRuleProfile: base.reactionRuleProfile,
      typeDogma: base.typeDogma
    )
  }

  private func dropMarketGroupTable(at url: URL) throws {
    try dropTable("market_groups", at: url)
  }

  private func dropTable(_ name: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      sqlite3_close(database)
      throw StaticCatalogError.database("fixture-open")
    }
    defer { sqlite3_close(database) }
    guard
      sqlite3_exec(database, "DROP TABLE \(name)", nil, nil, nil)
        == SQLITE_OK
    else {
      throw StaticCatalogError.database("fixture-drop")
    }
  }

  private func schemaNames(type: String, at url: URL) throws -> Set<String> {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      sqlite3_close(database)
      throw StaticCatalogError.database("fixture-open")
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT name FROM sqlite_master WHERE type = '\(type)'",
        -1,
        &statement,
        nil
      ) == SQLITE_OK
    else {
      throw StaticCatalogError.database("fixture-prepare")
    }
    defer { sqlite3_finalize(statement) }
    var names = Set<String>()
    while sqlite3_step(statement) == SQLITE_ROW {
      if let text = sqlite3_column_text(statement, 0) {
        names.insert(String(cString: text))
      }
    }
    return names
  }

  private func scalarCount(_ query: String, at url: URL) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      sqlite3_close(database)
      throw StaticCatalogError.database("fixture-open")
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
      sqlite3_step(statement) == SQLITE_ROW
    else {
      sqlite3_finalize(statement)
      throw StaticCatalogError.database("fixture-count")
    }
    defer { sqlite3_finalize(statement) }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func withTypeDogma(
    _ base: StaticDataCatalogSnapshot,
    _ typeDogma: [StaticTypeDogmaSnapshot]
  ) throws -> StaticDataCatalogSnapshot {
    try StaticDataCatalogSnapshot(
      buildNumber: base.buildNumber,
      contentSHA256: base.contentSHA256,
      officialArchiveURL: base.officialArchiveURL,
      sourceFormat: base.sourceFormat,
      categories: base.categories,
      groups: base.groups,
      itemTypes: base.itemTypes,
      typeMaterials: base.typeMaterials,
      blueprints: base.blueprints,
      decryptors: base.decryptors,
      marketGroups: base.marketGroups,
      reactionRuleProfile: base.reactionRuleProfile,
      typeDogma: typeDogma
    )
  }

  /// The same records the package fixture writes to `typeDogma.jsonl`.
  private func facilityTypeDogma() throws -> [StaticTypeDogmaSnapshot] {
    struct Record: Decodable {
      struct Attribute: Decodable {
        let attributeID: Int64
        let value: Double
      }
      let _key: Int64
      let dogmaAttributes: [Attribute]
    }
    return try Self.facilityDogmaLines.split(separator: "\n").map { line in
      let record = try JSONDecoder().decode(
        Record.self,
        from: Data(line.utf8)
      )
      return StaticTypeDogmaSnapshot(
        itemTypeID: record._key,
        attributeValues: Dictionary(
          uniqueKeysWithValues: record.dogmaAttributes.map {
            ($0.attributeID, $0.value)
          }
        )
      )
    }
  }

  /// Manufacturing variants around the base fixture: several ordered
  /// materials, a second product, one product offered by two blueprints and
  /// one blueprint with an unresolved material.
  private func definitionFixture(build: Int) throws
    -> StaticDataCatalogSnapshot
  {
    let base = try fixture(
      build: build,
      productName: "Parity Ship",
      includeReaction: true
    )
    func material(_ typeID: Int64, _ quantity: Int64, _ sortOrder: Int)
      -> StaticBlueprintMaterialSnapshot
    {
      StaticBlueprintMaterialSnapshot(
        itemTypeID: typeID,
        quantity: quantity,
        sortOrder: sortOrder
      )
    }
    func manufacturing(
      _ blueprintTypeID: Int64,
      maxProductionLimit: Int64? = 10,
      seconds: Int64,
      materials: [StaticBlueprintMaterialSnapshot],
      products: [StaticBlueprintProductSnapshot]
    ) -> StaticBlueprintSnapshot {
      StaticBlueprintSnapshot(
        blueprintTypeID: blueprintTypeID,
        maxProductionLimit: maxProductionLimit,
        activities: [
          StaticBlueprintActivitySnapshot(
            activity: .manufacturing,
            timeSeconds: seconds,
            materials: materials,
            products: products
          )
        ]
      )
    }
    let extraTypes = [
      itemType(id: 600, name: "Zeta Module"),
      itemType(id: 601, name: "alpha Charge"),
      itemType(id: 602, name: "Twin Product"),
      itemType(id: 603, name: "Broken Product"),
      itemType(id: 610, name: "Zeta Module Blueprint"),
      itemType(id: 611, name: "Alpha Charge Blueprint"),
      itemType(id: 612, name: "Twin Blueprint A"),
      itemType(id: 613, name: "Twin Blueprint B"),
      itemType(id: 614, name: "Broken Blueprint"),
      itemType(id: 620, name: "Material A"),
      itemType(id: 621, name: "Material B"),
      itemType(id: 622, name: "Material C"),
    ]
    let extraBlueprints = [
      manufacturing(
        610,
        seconds: 300,
        materials: [material(621, 5, 1), material(622, 9, 2), material(620, 3, 0)],
        products: [
          StaticBlueprintProductSnapshot(
            itemTypeID: 600,
            quantity: 1,
            probability: nil,
            sortOrder: 0
          )
        ]
      ),
      manufacturing(
        611,
        maxProductionLimit: nil,
        seconds: 120,
        materials: [material(620, 1, 0)],
        products: [
          StaticBlueprintProductSnapshot(
            itemTypeID: 622,
            quantity: 1,
            probability: 0.5,
            sortOrder: 1
          ),
          StaticBlueprintProductSnapshot(
            itemTypeID: 601,
            quantity: 100,
            probability: nil,
            sortOrder: 0
          ),
        ]
      ),
      manufacturing(
        612,
        seconds: 60,
        materials: [material(620, 2, 0)],
        products: [
          StaticBlueprintProductSnapshot(
            itemTypeID: 602,
            quantity: 1,
            probability: nil,
            sortOrder: 0
          )
        ]
      ),
      manufacturing(
        613,
        seconds: 90,
        materials: [material(621, 4, 0)],
        products: [
          StaticBlueprintProductSnapshot(
            itemTypeID: 602,
            quantity: 2,
            probability: nil,
            sortOrder: 0
          )
        ]
      ),
      manufacturing(
        614,
        seconds: 60,
        materials: [
          StaticBlueprintMaterialSnapshot(
            itemTypeID: 9_999,
            typeIsResolved: false,
            quantity: 1,
            sortOrder: 0
          )
        ],
        products: [
          StaticBlueprintProductSnapshot(
            itemTypeID: 603,
            quantity: 1,
            probability: nil,
            sortOrder: 0
          )
        ]
      ),
    ]
    return try StaticDataCatalogSnapshot(
      buildNumber: base.buildNumber,
      contentSHA256: base.contentSHA256,
      officialArchiveURL: base.officialArchiveURL,
      sourceFormat: base.sourceFormat,
      categories: base.categories,
      groups: base.groups,
      itemTypes: base.itemTypes + extraTypes,
      typeMaterials: base.typeMaterials,
      blueprints: base.blueprints + extraBlueprints,
      decryptors: base.decryptors,
      marketGroups: base.marketGroups,
      reactionRuleProfile: base.reactionRuleProfile
    )
  }

  private func fixture(
    build: Int,
    productName: String,
    includeReaction: Bool = false,
    includeMoonMaterials: Bool = false,
    includeMinerals: Bool = false,
    includeCompressedOre: Bool = false,
    includeReprocessingReference: Bool = false,
    productPackagedVolume: Double? = 1
  ) throws -> StaticDataCatalogSnapshot {
    let category = StaticItemCategorySnapshot(
      externalID: 10,
      name: "Fixture",
      published: true
    )
    let group = StaticItemGroupSnapshot(
      externalID: 20,
      categoryExternalID: 10,
      name: "Fixture Group",
      published: true
    )
    let moonMaterialGroup = StaticItemGroupSnapshot(
      externalID: 427,
      categoryExternalID: 10,
      name: "Moon Materials",
      published: true
    )
    let mineralGroup = StaticItemGroupSnapshot(
      externalID: 18,
      categoryExternalID: 10,
      name: "Mineral",
      published: true
    )
    let skillCategory = StaticItemCategorySnapshot(
      externalID: 16,
      name: "Skill",
      published: true
    )
    let scienceGroup = StaticItemGroupSnapshot(
      externalID: 270,
      categoryExternalID: 16,
      name: "Science",
      published: true
    )
    let structureCategory = StaticItemCategorySnapshot(
      externalID: 65,
      name: "Structure",
      published: true
    )
    let structureModuleCategory = StaticItemCategorySnapshot(
      externalID: 66,
      name: "Structure Module",
      published: true
    )
    let engineeringComplexGroup = StaticItemGroupSnapshot(
      externalID: 1_404,
      categoryExternalID: 65,
      name: "Engineering Complex",
      published: true
    )
    let mediumRigGroup = StaticItemGroupSnapshot(
      externalID: 1_830,
      categoryExternalID: 66,
      name: "Structure Engineering Rig M - Advanced Small Ship ME",
      published: true
    )
    let engineeringServiceGroup = StaticItemGroupSnapshot(
      externalID: 1_415,
      categoryExternalID: 66,
      name: "Structure Engineering Service Module",
      published: true
    )
    let refineryGroup = StaticItemGroupSnapshot(
      externalID: 1_406,
      categoryExternalID: 65,
      name: "Refinery",
      published: true
    )
    let largeReprocessingRigGroup = StaticItemGroupSnapshot(
      externalID: 1_944,
      categoryExternalID: 66,
      name: "Structure Resource Rig L",
      published: true
    )
    let refineryServiceGroup = StaticItemGroupSnapshot(
      externalID: 1_322,
      categoryExternalID: 66,
      name: "Structure Resource Processing Service Module",
      published: true
    )
    var itemTypes = [
      itemType(
        id: 1,
        name: productName,
        packagedVolume: productPackagedVolume,
        metaGroupID: 2,
        techLevel: 2
      ),
      itemType(id: 2, name: "Fixture Mineral"),
      itemType(id: 99, name: "Unpublished Test Blueprint", published: false),
      itemType(id: 100, name: "Fixture Blueprint", basePrice: 1_000),
      StaticItemTypeSnapshot(
        externalID: 200,
        groupExternalID: 270,
        categoryExternalID: 16,
        marketGroupExternalID: nil,
        name: "Fixture Encryption Methods",
        description: nil,
        volume: 0.01,
        packagedVolume: 0.01,
        basePrice: nil,
        portionSize: 1,
        published: true,
        iconExternalID: nil
      ),
      referenceItemType(
        id: 35_825,
        groupID: 1_404,
        categoryID: 65,
        name: "Raitaru"
      ),
      referenceItemType(
        id: 43_855,
        groupID: 1_830,
        categoryID: 66,
        name:
          "Standup M-Set Advanced Small Ship Manufacturing Material Efficiency I"
      ),
      referenceItemType(
        id: 43_722,
        groupID: 1_830,
        categoryID: 66,
        name: "Standup L-Set Invention Optimization I"
      ),
      referenceItemType(
        id: 35_891,
        groupID: 1_415,
        categoryID: 66,
        name: "Standup Research Lab I"
      ),
    ]
    if includeReaction {
      itemTypes.append(itemType(id: 3, name: "Fixture Reaction Product"))
      itemTypes.append(itemType(id: 4, name: "Fixture Reaction Input"))
      itemTypes.append(itemType(id: 101, name: "Fixture Reaction Formula"))
    }
    if includeReprocessingReference {
      itemTypes.append(
        referenceItemType(
          id: 35_836,
          groupID: 1_406,
          categoryID: 65,
          name: "Tatara"
        )
      )
      itemTypes.append(
        referenceItemType(
          id: 46_640,
          groupID: 1_944,
          categoryID: 66,
          name: "Standup L-Set Reprocessing Monitor II"
        )
      )
      itemTypes.append(
        referenceItemType(
          id: 35_899,
          groupID: 1_322,
          categoryID: 66,
          name: "Standup Reprocessing Facility I"
        )
      )
    }
    if includeCompressedOre {
      itemTypes.append(
        itemType(
          id: 500,
          name: "Compressed Fixture Ore",
          packagedVolume: 0.15
        )
      )
      itemTypes.append(
        StaticItemTypeSnapshot(
          externalID: 12_104,
          groupExternalID: 270,
          categoryExternalID: 16,
          marketGroupExternalID: nil,
          name: "Fixture Ore Processing",
          description: nil,
          volume: 0.01,
          packagedVolume: 0.01,
          basePrice: nil,
          portionSize: 1,
          published: true,
          iconExternalID: nil
        )
      )
    }
    if includeMoonMaterials {
      itemTypes.append(
        referenceItemType(
          id: 16_634,
          groupID: 427,
          categoryID: 10,
          name: "Atmospheric Gases"
        )
      )
      itemTypes.append(
        referenceItemType(
          id: 16_643,
          groupID: 427,
          categoryID: 10,
          name: "Cadmium"
        )
      )
      itemTypes.append(
        StaticItemTypeSnapshot(
          externalID: 99_999,
          groupExternalID: 427,
          categoryExternalID: 10,
          marketGroupExternalID: nil,
          name: "Unpublished Moon Material",
          description: nil,
          volume: 1,
          packagedVolume: 1,
          basePrice: nil,
          portionSize: 1,
          published: false,
          iconExternalID: nil
        )
      )
    }
    if includeMinerals {
      itemTypes.append(
        referenceItemType(
          id: 34,
          groupID: 18,
          categoryID: 10,
          name: "Tritanium"
        )
      )
      itemTypes.append(
        referenceItemType(
          id: 35,
          groupID: 18,
          categoryID: 10,
          name: "Pyerite"
        )
      )
      itemTypes.append(
        referenceItemType(
          id: 92_572,
          groupID: 18,
          categoryID: 10,
          name: "Crystalline Kangite"
        )
      )
      itemTypes.append(
        StaticItemTypeSnapshot(
          externalID: 99_998,
          groupExternalID: 18,
          categoryExternalID: 10,
          marketGroupExternalID: nil,
          name: "Unpublished Mineral",
          description: nil,
          volume: 1,
          packagedVolume: 1,
          basePrice: nil,
          portionSize: 1,
          published: false,
          iconExternalID: nil
        )
      )
    }
    let blueprint = StaticBlueprintSnapshot(
      blueprintTypeID: 100,
      maxProductionLimit: 10,
      activities: [
        StaticBlueprintActivitySnapshot(
          activity: .manufacturing,
          timeSeconds: 60,
          materials: [
            StaticBlueprintMaterialSnapshot(
              itemTypeID: 2,
              quantity: 7,
              sortOrder: 0
            )
          ],
          products: [
            StaticBlueprintProductSnapshot(
              itemTypeID: 1,
              quantity: 1,
              probability: nil,
              sortOrder: 0
            )
          ]
        ),
        StaticBlueprintActivitySnapshot(
          activity: .researchMaterial,
          timeSeconds: 105,
          materials: [],
          products: [],
          skills: [
            StaticBlueprintSkillSnapshot(
              itemTypeID: 2,
              level: 4,
              sortOrder: 0
            )
          ]
        ),
        StaticBlueprintActivitySnapshot(
          activity: .researchTime,
          timeSeconds: 105,
          materials: [],
          products: []
        ),
      ]
    )
    let unpublishedTestBlueprint = StaticBlueprintSnapshot(
      blueprintTypeID: 99,
      maxProductionLimit: 10,
      activities: [
        StaticBlueprintActivitySnapshot(
          activity: .manufacturing,
          timeSeconds: 1,
          materials: [
            StaticBlueprintMaterialSnapshot(
              itemTypeID: 2,
              quantity: 999,
              sortOrder: 0
            )
          ],
          products: [
            StaticBlueprintProductSnapshot(
              itemTypeID: 1,
              quantity: 20,
              probability: nil,
              sortOrder: 0
            )
          ]
        )
      ]
    )
    var blueprints = [unpublishedTestBlueprint, blueprint]
    if includeReaction {
      blueprints.append(
        StaticBlueprintSnapshot(
          blueprintTypeID: 101,
          maxProductionLimit: nil,
          activities: [
            StaticBlueprintActivitySnapshot(
              activity: .reaction,
              timeSeconds: 180,
              materials: [
                StaticBlueprintMaterialSnapshot(
                  itemTypeID: 4,
                  quantity: 100,
                  sortOrder: 0
                )
              ],
              products: [
                StaticBlueprintProductSnapshot(
                  itemTypeID: 3,
                  quantity: 200,
                  probability: nil,
                  sortOrder: 0
                )
              ]
            )
          ]
        )
      )
    }
    let hash = String(repeating: String(build), count: 64)
    let reactionRules = ReactionRuleProfile(
      catalogBuildNumber: build,
      catalogContentSHA256: hash,
      verificationStatus: .needsReview,
      verifiedAt: .distantPast,
      sourceURLs: ["fixture://type-dogma"],
      formulaGroupKinds: [:],
      facilities: [],
      reactors: [],
      rigs: [],
      reactionsSkillTypeID: 1,
      skillTimeBonusBasisPointsPerLevel: -400
    )
    let typeMaterials =
      includeCompressedOre
      ? [
        StaticTypeMaterialSnapshot(
          sourceTypeID: 500,
          reprocessingSkillTypeID: 12_104,
          materials: [
            StaticTypeMaterialOutputSnapshot(
              materialTypeID: 2,
              quantity: 415
            )
          ]
        )
      ] : []
    return try StaticDataCatalogSnapshot(
      buildNumber: build,
      contentSHA256: hash,
      officialArchiveURL:
        "https://developers.eveonline.com/static-data/tranquility/eve-online-static-data-\(build)-jsonl.zip",
      sourceFormat: .jsonLines,
      categories: [
        category, skillCategory, structureCategory, structureModuleCategory,
      ],
      groups: [
        group, scienceGroup, engineeringComplexGroup, mediumRigGroup,
        engineeringServiceGroup, refineryGroup, largeReprocessingRigGroup,
        refineryServiceGroup,
      ] + (includeMoonMaterials ? [moonMaterialGroup] : [])
        + (includeMinerals ? [mineralGroup] : []),
      itemTypes: itemTypes,
      typeMaterials: typeMaterials,
      blueprints: blueprints,
      reactionRuleProfile: reactionRules
    )
  }

  private func itemType(
    id: Int64,
    name: String,
    basePrice: Double? = nil,
    published: Bool = true,
    packagedVolume: Double? = 1,
    metaGroupID: Int64? = nil,
    techLevel: Int64? = nil
  ) -> StaticItemTypeSnapshot {
    StaticItemTypeSnapshot(
      externalID: id,
      groupExternalID: 20,
      categoryExternalID: 10,
      marketGroupExternalID: nil,
      name: name,
      description: nil,
      volume: 1,
      packagedVolume: packagedVolume,
      basePrice: basePrice,
      portionSize: 1,
      published: published,
      iconExternalID: nil,
      metaGroupExternalID: metaGroupID,
      techLevel: techLevel
    )
  }

  private func referenceItemType(
    id: Int64,
    groupID: Int64,
    categoryID: Int64,
    name: String
  ) -> StaticItemTypeSnapshot {
    StaticItemTypeSnapshot(
      externalID: id,
      groupExternalID: groupID,
      categoryExternalID: categoryID,
      marketGroupExternalID: nil,
      name: name,
      description: nil,
      volume: 1,
      packagedVolume: 1,
      basePrice: nil,
      portionSize: 1,
      published: true,
      iconExternalID: nil
    )
  }

  private func writeFacilityPackage(
    baseURL: URL,
    snapshot: StaticDataCatalogSnapshot
  ) throws {
    let package =
      baseURL
      .appendingPathComponent("packages", isDirectory: true)
      .appendingPathComponent("fixture.evesde", isDirectory: true)
    try FileManager.default.createDirectory(
      at: package,
      withIntermediateDirectories: true
    )
    let manifest =
      """
      {
        "snapshot": {
          "buildNumber": \(snapshot.buildNumber),
          "contentSHA256": "\(snapshot.contentSHA256)"
        }
      }
      """
    try Data(manifest.utf8).write(
      to: package.appendingPathComponent("manifest.json")
    )
    try Data(Self.facilityDogmaLines.utf8).write(
      to: package.appendingPathComponent("typeDogma.jsonl")
    )
  }

  private static let facilityDogmaLines =
    """
    {"_key":35825,"dogmaAttributes":[{"attributeID":1137,"value":3},{"attributeID":1547,"value":2},{"attributeID":2600,"value":0.99},{"attributeID":2601,"value":0.97},{"attributeID":2602,"value":0.85}]}
    {"_key":43855,"dogmaAttributes":[{"attributeID":1547,"value":2},{"attributeID":2356,"value":1.9},{"attributeID":2357,"value":2.1},{"attributeID":2593,"value":0},{"attributeID":2594,"value":-2}]}
    {"_key":43722,"dogmaAttributes":[{"attributeID":1547,"value":3},{"attributeID":2356,"value":1.9},{"attributeID":2357,"value":2.1},{"attributeID":2593,"value":-20},{"attributeID":2595,"value":-10}]}
    {"_key":35891,"dogmaAttributes":[{"attributeID":1298,"value":1657},{"attributeID":1299,"value":1404},{"attributeID":1300,"value":1406}]}
    {"_key":35836,"dogmaAttributes":[{"attributeID":1137,"value":3},{"attributeID":1547,"value":3},{"attributeID":2722,"value":5.5}]}
    {"_key":46640,"dogmaAttributes":[{"attributeID":717,"value":0.53},{"attributeID":1547,"value":3},{"attributeID":2356,"value":1.06},{"attributeID":2357,"value":1.12}]}
    {"_key":35899,"dogmaAttributes":[{"attributeID":717,"value":0.5},{"attributeID":2444,"value":0.5},{"attributeID":2445,"value":0.5},{"attributeID":2448,"value":0.5},{"attributeID":3262,"value":0.8}]}
    """
}

private struct FixtureStreamingMapper: StaticDataCatalogStreamingMapping {
  let snapshot: StaticDataCatalogSnapshot

  func packageMetadata(at packageURL: URL) async throws
    -> StaticDataCatalogPackageMetadata
  {
    StaticDataCatalogPackageMetadata(
      buildNumber: snapshot.buildNumber,
      contentSHA256: snapshot.contentSHA256,
      officialArchiveURL: snapshot.officialArchiveURL,
      sourceFormat: snapshot.sourceFormat
    )
  }

  func streamStagingPackage(
    at packageURL: URL,
    batchSize: Int,
    consume: @escaping StaticDataCatalogBatchConsumer
  ) async throws -> StaticDataCatalogStreamResult {
    try await consume(.categories(snapshot.categories))
    try await consume(.groups(snapshot.groups))
    if !snapshot.marketGroups.isEmpty {
      try await consume(.marketGroups(snapshot.marketGroups))
    }
    try await consume(.itemTypes(snapshot.itemTypes))
    if !snapshot.typeMaterials.isEmpty {
      try await consume(.typeMaterials(snapshot.typeMaterials))
    }
    try await consume(.blueprints(snapshot.blueprints))
    if let profile = snapshot.reactionRuleProfile {
      try await consume(.reactionRuleProfile(profile))
    }
    if !snapshot.typeDogma.isEmpty {
      try await consume(.typeDogma(snapshot.typeDogma))
    }
    return StaticDataCatalogStreamResult(
      metadata: try await packageMetadata(at: packageURL),
      counts: snapshot.counts
    )
  }
}
