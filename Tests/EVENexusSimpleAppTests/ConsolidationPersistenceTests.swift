import Foundation
import SwiftData
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

@MainActor
@Suite("Additive workspace migration", .serialized)
struct ConsolidationPersistenceTests {
  @Test func fullRestoreValidatorMigratesV1WithoutNormalStartupSideEffects() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("v1-restore-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.store")
    try seedRecoveryV1(source)
    let candidate = root.appendingPathComponent("candidate.store")
    try ConsolidationBackup.snapshotSQLite(source: source, destination: candidate)
    let counts = try FullStoreRecovery.validateDirect(candidate)
    #expect(counts.count == 13)
    #expect(counts["Characters"] == 1)
    #expect(counts["App settings"] == 1)
    #expect(counts["Consolidation workspaces"] == 0)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-backups").path))
  }

  private func seedRecoveryV1(_ store: URL) throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV1.self)
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("EVENexusSimple", schema: schema, url: store, cloudKitDatabase: .none)])
    let context = ModelContext(container)
    context.insert(EVENexusSchemaV1.StoredCharacter(characterID: 42, characterName: "Fixture", authorizationSnapshot: try JSONEncoder().encode(AuthorizationSnapshot(characterID: 42, characterName: "Fixture", scopes: []))))
    context.insert(EVENexusSchemaV1.AppSetting(key: "fixture", value: "retained"))
    try context.save()
  }

  @Test func fullRestoreValidatorMigratesV2AndReadsEveryV3Model() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("all-model-restore-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppDataPaths.resolve(applicationSupportRoot: root, fileExists: { _ in false })
    try paths.prepareDirectories()
    let bytes = try JSONEncoder().encode(makePlan())
    try seedV2(paths: paths, bytes: bytes, rowID: UUID())
    let candidate = root.appendingPathComponent("candidate.store")
    try ConsolidationBackup.snapshotSQLite(source: paths.swiftDataStoreURL, destination: candidate)
    let initial = try FullStoreRecovery.validateDirect(candidate)
    #expect(initial.count == 13)
    #expect(initial["Plans"] == 2)
    #expect(initial["Planner drafts"] == 1)
    #expect(initial["Production overview rows"] == 1)
    #expect(initial["Consolidation workspaces"] == 0)
    try populateRemainingRecoveryModels(candidate, bytes: bytes)
    let all = try FullStoreRecovery.validateDirect(candidate)
    #expect(all.count == 13)
    #expect(all.values.allSatisfy { $0 > 0 })
    let restored = root.appendingPathComponent("restored.store")
    try ConsolidationBackup.snapshotSQLite(source: candidate, destination: restored)
    #expect(try FullStoreRecovery.validateDirect(restored) == all)
  }

  private func populateRemainingRecoveryModels(_ store: URL, bytes: Data) throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("EVENexusSimple", schema: schema, url: store, cloudKitDatabase: .none)])
    let c = ModelContext(container)
    c.insert(StoredProductionBasis(id: UUID(), name: "Fixture", encodedBasis: try JSONEncoder().encode(ProductionBasis())))
    c.insert(StoredManufacturingProfile(id: UUID(), name: "Fixture", encodedProfile: try JSONEncoder().encode(ManufacturingProfile())))
    c.insert(StoredReactionProfile(id: UUID(), name: "Fixture", encodedProfile: try JSONEncoder().encode(ReactionProfile())))
    c.insert(StoredCharacter(characterID: 42, characterName: "Fixture", authorizationSnapshot: try JSONEncoder().encode(AuthorizationSnapshot(characterID: 42, characterName: "Fixture", scopes: []))))
    c.insert(StoredStockTarget(typeID: 34, typeName: "Fixture", targetQuantity: 19))
    c.insert(StoredProductionRecord(planID: UUID(), name: "Fixture", input: "input", manualStockInput: "stock", snapshot: bytes, sdeBuild: 1, esiCompatibilityDate: "fixture", priceTimestamp: .now, ruleVersion: "fixture"))
    c.insert(StoredSDEActivationPointer(buildNumber: 1, contentSHA256: "fixture"))
    c.insert(StoredESISnapshotMetadata(characterID: 42, domain: "fixture", freshness: "fresh", provider: "fixture", sourceVersion: "1", sourceSnapshotID: UUID(), capturedAt: .now, diagnostics: []))
    c.insert(AppSetting(key: "fixture", value: "retained"))
    c.insert(StoredConsolidationWorkspace(payload: try JSONEncoder().encode(ConsolidationWorkspace()), revision: 0))
    try c.save()
  }

  @Test(arguments: ["not base64!", Data("{invalid json".utf8).base64EncodedString()])
  func restoreValidatorRejectsMalformedKnownSettingPayload(value: String) throws {
    for key in [AppSettingKey.industryJobs(characterID: 42), AppSettingKey.openOrders(characterID: 42),
      AppSettingKey.privateContracts(characterID: 42), AppSettingKey.corporationWallet(characterID: 42), AppSettingKey.dashboardWealthHistory] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("setting-restore-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let source = root.appendingPathComponent("source.store")
      try seedRecoverySetting(source, key: key, value: value)
      let candidate = root.appendingPathComponent("candidate.store")
      try ConsolidationBackup.snapshotSQLite(source: source, destination: candidate)
      #expect(throws: (any Error).self) { try FullStoreRecovery.validateDirect(candidate) }
    }
  }

  private func seedRecoverySetting(_ store: URL, key: String, value: String) throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("EVENexusSimple", schema: schema, url: store, cloudKitDatabase: .none)])
    let context = ModelContext(container)
    context.insert(AppSetting(key: key, value: value))
    try context.save()
  }

  @Test func restoreValidatorAcceptsLegitimateEmptyEVEStore() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("empty-restore-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.store")
    try seedEmptyRecoveryStore(source)
    let candidate = root.appendingPathComponent("candidate.store")
    try ConsolidationBackup.snapshotSQLite(source: source, destination: candidate)
    let counts = try FullStoreRecovery.validateDirect(candidate)
    #expect(counts.count == 13)
    #expect(counts.values.allSatisfy { $0 == 0 })
  }

  private func seedEmptyRecoveryStore(_ store: URL) throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("EVENexusSimple", schema: schema, url: store, cloudKitDatabase: .none)])
    try ModelContext(container).save()
  }

  @Test func restoreValidatorRefusesUnrelatedSQLiteDatabase() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("unrelated-restore-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let candidate = root.appendingPathComponent("candidate.store")
    let sqlite = Process()
    sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    sqlite.arguments = [candidate.path, "CREATE TABLE unrelated(value INTEGER); INSERT INTO unrelated VALUES(42);"]
    try sqlite.run()
    sqlite.waitUntilExit()
    #expect(sqlite.terminationStatus == 0)
    #expect(throws: (any Error).self) { try FullStoreRecovery.validateDirect(candidate) }
  }

  @Test func v2MigrationPreservesHistoryAndBootstrapIsIdempotent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-schema-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppDataPaths.resolve(applicationSupportRoot: root, fileExists: { _ in false })
    try paths.prepareDirectories()
    let bytes = try JSONEncoder().encode(makePlan())
    let rowID = UUID()
    try seedV2(paths: paths, bytes: bytes, rowID: rowID)
    let container = try AppPersistence.open(paths: paths)
    let c = ModelContext(container)
    let rows = try c.fetch(FetchDescriptor<StoredProductionOverviewRow>())
    #expect(rows.count == 1)
    #expect(rows[0].id == rowID)
    #expect(rows[0].sequenceNumber == 123)
    #expect(rows[0].sourceSnapshot == bytes)
    #expect(rows[0].materialCost == 12.3456789)
    #expect(rows[0].indexCost == nil)
    #expect(rows[0].soldUnits == 3)
    #expect(rows[0].salePricePerUnit == 5.25)
    let first = ConsolidationController()
    try first.start(container: container)
    // No production project is created; the planner draft and plans stay where they are.
    #expect(first.workspace.projects.isEmpty)
    #expect(first.workspace.reservations.isEmpty && first.workspace.purchases.isEmpty)
    #expect(first.workspace.evidence.isEmpty)
    #expect(first.workspace.sales.isEmpty)
    let draft = try #require(try c.fetch(FetchDescriptor<StoredPlannerDraft>()).first)
    #expect(draft.input == "unsaved draft")
    #expect(draft.manualStockInput == "Tritanium | 19")
    let second = ConsolidationController()
    try second.start(container: container)
    #expect(second.workspace.projects.isEmpty)
    #expect(try c.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).count == 1)
    let backups = paths.dataRoot.appendingPathComponent("migration-backups/swiftdata")
    #expect(
      FileManager.default.fileExists(
        atPath: backups.appendingPathComponent("canonical-schema-v3.complete").path))
    #expect(try c.fetch(FetchDescriptor<StoredPlan>()).count == 2)
  }

  @Test func verifiedV2BackupRestoresAfterInterruptedWorkspaceInitialization() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-recovery-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppDataPaths.resolve(applicationSupportRoot: root, fileExists: { _ in false })
    try paths.prepareDirectories()
    let bytes = try JSONEncoder().encode(makePlan())
    let rowID = UUID()
    try seedV2(paths: paths, bytes: bytes, rowID: rowID)
    let backup = root.appendingPathComponent("before-migration.nexusbackup")
    let preferences = try PropertyListSerialization.data(
      fromPropertyList: [:], format: .binary, options: 0)
    try ConsolidationBackup.create(
      dataRoot: paths.dataRoot, destination: backup, defaults: preferences, schema: 2)
    try simulateInterruptedWorkspaceInitialization(paths: paths)
    try ConsolidationBackup.scheduleRestore(backup, paths: paths)
    #expect(
      try ConsolidationBackup.applyPendingRestore(paths: paths, defaults: preferences, schema: 3)
        == preferences)
    let recovered = try AppPersistence.open(paths: paths)
    let controller = ConsolidationController()
    try controller.start(container: recovered)
    #expect(controller.workspace.projects.isEmpty)
    #expect(try ModelContext(recovered).fetch(FetchDescriptor<StoredPlan>()).contains { $0.snapshot == bytes })
    let rows = try ModelContext(recovered).fetch(FetchDescriptor<StoredProductionOverviewRow>())
    #expect(rows.count == 1 && rows[0].id == rowID && rows[0].sequenceNumber == 123)
    #expect(rows[0].sourceSnapshot == bytes && rows[0].materialCost == 12.3456789)
    let retained = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(retained.contains { $0.hasPrefix(".eve-prior-") })
    #expect(retained.contains { $0.hasPrefix("EVE-before-restore-") })
  }

  private func simulateInterruptedWorkspaceInitialization(paths: AppDataPaths) throws {
    let container = try AppPersistence.open(paths: paths)
    let context = ModelContext(container)
    // Simulate an incomplete new payload while retaining the old entities and a healthy SQLite store.
    context.insert(StoredConsolidationWorkspace(payload: Data("{interrupted".utf8), revision: 0))
    try context.save()
    let controller = ConsolidationController()
    #expect(throws: (any Error).self) { try controller.start(container: container) }
  }

  @Test func intermediateWorkspaceEditRequiresFreshConfirmation() throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let controller = ConsolidationController()
    try controller.start(container: container)
    #expect(controller.workspace.projects.isEmpty)
    controller.propose(["Add receipt"]) {
      try $0.addEvidence(
        ProductionSaleEvidence(
          id: "1:transaction:1", typeID: 34, quantity: 1, unitPrice: try ISKAmount.parse("1"),
          recordedAt: .now, source: "Wallet"))
    }
    try controller.edit { $0.warningThresholds[34] = 1 }
    controller.confirm(catalogBuild: nil)
    #expect(controller.workspace.evidence.isEmpty)
    #expect(controller.error != nil)
  }

  @Test func changingStockInvalidatesPreview() throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let controller = ConsolidationController()
    try controller.start(container: container)
    controller.updateESIStock([34: 10])
    controller.propose(["Add receipt"]) {
      try $0.addEvidence(
        ProductionSaleEvidence(
          id: "1:transaction:1", typeID: 34, quantity: 1, unitPrice: try ISKAmount.parse("1"),
          recordedAt: .now, source: "Wallet"))
    }
    controller.updateESIStock([34: 2])
    controller.confirm(catalogBuild: nil)
    #expect(controller.workspace.evidence.isEmpty)
    #expect(controller.error != nil)
  }

  private func seedV2(paths: AppDataPaths, bytes: Data, rowID: UUID) throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV2.self)
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(
          "EVENexusSimple", schema: schema, url: paths.swiftDataStoreURL, cloudKitDatabase: .none)
      ])
    let context = ModelContext(container)
    context.insert(StoredPlannerDraft(input: "unsaved draft", manualStockInput: "Tritanium | 19"))
    for active in [false, true] {
      context.insert(
        StoredPlan(
          id: UUID(), name: active ? "Current" : "History", input: "saved plan", snapshot: bytes,
          sdeBuild: 1, esiCompatibilityDate: "fixture", priceTimestamp: .now,
          ruleVersion: "fixture", isActive: active))
    }
    context.insert(
      StoredProductionOverviewRow(
        id: rowID, sequenceNumber: 123, recordedAt: Date(timeIntervalSince1970: 100),
        planID: UUID(), requestID: UUID(), productName: "Fixture", runs: 1, materialEfficiency: 2,
        timeEfficiency: 4,
        systemName: "Fixture system", units: 7, materialCost: 12.3456789, indexCost: nil,
        blueprintCost: 0, marketTax: nil,
        salePricePerUnit: 5.25, soldUnits: 3, sourceSnapshot: bytes, sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        priceTimestamp: Date(timeIntervalSince1970: 90), ruleVersion: "fixture"))
    try context.save()
  }
  private func makePlan(
    stockAllocations: [StockAllocation] = [],
    includeEarlierMaterialNode: Bool = false,
    blueprintCostISK: Double? = 10,
    automaticBlueprintCost: Double? = nil
  ) -> IndustryPlanSnapshot {
    let requestID = UUID()
    let request = ProductionRequestLine(
      id: requestID,
      lineNumber: 1,
      productName: "Fixture Ship",
      wantedQuantity: 10,
      materialEfficiency: 4,
      timeEfficiency: 2,
      blueprintKind: blueprintCostISK == nil ? nil : .bpc,
      blueprintCostISK: blueprintCostISK
    )
    var nodes: [PlanNode] = []
    if includeEarlierMaterialNode {
      nodes.append(
        PlanNode(
          id: UUID(),
          typeID: 34,
          name: "Fixture Material",
          requiredQuantity: 20,
          action: .buy,
          activity: nil,
          runs: nil,
          materialEfficiency: nil,
          timeEfficiency: nil,
          children: [],
          topLevelRequestID: requestID
        )
      )
    }
    nodes.append(
      PlanNode(
        id: UUID(),
        typeID: 100,
        name: "Fixture Ship",
        requiredQuantity: 10,
        action: .produce,
        activity: .manufacturing,
        runs: 1,
        materialEfficiency: 4,
        timeEfficiency: 2,
        children: [],
        topLevelRequestID: requestID
      )
    )
    return IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: [request],
      nodes: nodes,
      materials: [],
      stockAllocations: stockAllocations,
      jobs: [],
      materialCost: 100,
      installationCost: 20,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 100,
        purchasedMaterialCost: 100,
        stockMaterialCost: 0,
        blueprintCosts: automaticBlueprintCost.map {
          BlueprintCostBreakdown(
            entries: [],
            requestsWithoutEnteredCost: [],
            total: $0
          )
        },
        systemIndexCost: 20,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 20,
        logistics: nil,
        logisticsCost: 5,
        totalProductionCost: nil
      ),
      immediateSale: SaleScenarioResult(
        scenario: .immediateSale,
        grossRevenue: 200,
        salesTax: 10,
        brokerFee: 0,
        grossOrNetRevenue: 190,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: []
      ),
      listedSale: SaleScenarioResult(
        scenario: .listedSale,
        grossRevenue: 200,
        salesTax: 10,
        brokerFee: 2,
        grossOrNetRevenue: 188,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: []
      ),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: nil,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )
  }
}
