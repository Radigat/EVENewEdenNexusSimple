import EVEStaticDataKit
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Build-specific SQLite SDE catalog")
struct SQLiteStaticCatalogTests {
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
      try await catalog.productionDefinition(productTypeID: 1)?
        .blueprintTypeID == 100
    )
    #expect(
      try await catalog.productionDefinition(productTypeID: 1)?
        .activity.materials.first?.quantity == 7
    )
    #expect(
      try await catalog.industryClassification(productTypeID: 1)?
        .manufacturingCategory == .module
    )
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
  func readsFacilityAndRigRulesFromTheActiveValidatedPackage() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-simple-facility-sde-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent(
      "catalog-store",
      isDirectory: true
    )
    let catalog = SQLiteStaticCatalog(rootURL: root)
    let snapshot = try fixture(build: 3, productName: "Fixture Ship")
    _ = try await catalog.activate(snapshot)
    try writeFacilityPackage(baseURL: base, snapshot: snapshot)

    let reference = try await catalog.industryFacilityReferences()

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
  }

  private func fixture(
    build: Int,
    productName: String
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
    let itemTypes = [
      itemType(id: 1, name: productName),
      itemType(id: 2, name: "Fixture Mineral"),
      itemType(id: 99, name: "Unpublished Test Blueprint", published: false),
      itemType(id: 100, name: "Fixture Blueprint"),
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
        )
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
        engineeringServiceGroup,
      ],
      itemTypes: itemTypes,
      blueprints: [unpublishedTestBlueprint, blueprint],
      reactionRuleProfile: reactionRules
    )
  }

  private func itemType(
    id: Int64,
    name: String,
    published: Bool = true
  ) -> StaticItemTypeSnapshot {
    StaticItemTypeSnapshot(
      externalID: id,
      groupExternalID: 20,
      categoryExternalID: 10,
      marketGroupExternalID: nil,
      name: name,
      description: nil,
      volume: 1,
      packagedVolume: 1,
      basePrice: nil,
      portionSize: 1,
      published: published,
      iconExternalID: nil
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
    let dogma =
      """
      {"_key":35825,"dogmaAttributes":[{"attributeID":1137,"value":3},{"attributeID":1547,"value":2},{"attributeID":2600,"value":0.99},{"attributeID":2601,"value":0.97},{"attributeID":2602,"value":0.85}]}
      {"_key":43855,"dogmaAttributes":[{"attributeID":1547,"value":2},{"attributeID":2356,"value":1.9},{"attributeID":2357,"value":2.1},{"attributeID":2593,"value":0},{"attributeID":2594,"value":-2}]}
      {"_key":43722,"dogmaAttributes":[{"attributeID":1547,"value":3},{"attributeID":2356,"value":1.9},{"attributeID":2357,"value":2.1},{"attributeID":2593,"value":-20},{"attributeID":2595,"value":-10}]}
      {"_key":35891,"dogmaAttributes":[{"attributeID":1298,"value":1657},{"attributeID":1299,"value":1404},{"attributeID":1300,"value":1406}]}
      """
    try Data(dogma.utf8).write(
      to: package.appendingPathComponent("typeDogma.jsonl")
    )
  }
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
    try await consume(.itemTypes(snapshot.itemTypes))
    try await consume(.blueprints(snapshot.blueprints))
    if let profile = snapshot.reactionRuleProfile {
      try await consume(.reactionRuleProfile(profile))
    }
    return StaticDataCatalogStreamResult(
      metadata: try await packageMetadata(at: packageURL),
      counts: snapshot.counts
    )
  }
}
