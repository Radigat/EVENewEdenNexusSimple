import Foundation
import SwiftData
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

@MainActor
@Suite("Additive workspace migration", .serialized)
struct ConsolidationPersistenceTests {
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
    #expect(first.workspace.projects.count == 1)
    #expect(first.workspace.projects[0].input == "unsaved draft")
    #expect(first.workspace.projects[0].manualStockInput == "Tritanium | 19")
    #expect(first.workspace.projects[0].planSnapshot == bytes)
    #expect(first.workspace.evidence.isEmpty)
    #expect(first.workspace.sales.isEmpty)
    let second = ConsolidationController()
    try second.start(container: container)
    #expect(second.workspace.projects.count == 1)
    #expect(second.workspace.projects[0].id == first.workspace.projects[0].id)
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
    #expect(controller.workspace.projects.count == 1)
    #expect(controller.workspace.projects[0].planSnapshot == bytes)
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

  @Test func switchingProjectsPreservesIndependentDraftsAndRequiresFreshConfirmation() throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let controller = ConsolidationController()
    try controller.start(container: container)
    let a = try #require(controller.workspace.selectedProjectID)
    try controller.saveDraft(input: "Alpha", manualStockInput: "Stock A", supply: nil)
    try controller.edit { try $0.createProject(name: "Beta") }
    try controller.saveDraft(input: "Beta", manualStockInput: "Stock B", supply: nil)
    try controller.edit { $0.selectedProjectID = a }
    #expect(controller.workspace.selectedProject?.input == "Alpha")
    #expect(controller.workspace.selectedProject?.manualStockInput == "Stock A")
    controller.propose(["Create warehouse"]) { try $0.createWarehouse(name: "A") }
    try controller.saveDraft(input: "Changed", manualStockInput: "Stock A", supply: nil)
    controller.confirm(catalogBuild: nil)
    #expect(controller.workspace.warehouses.isEmpty)
    #expect(controller.error != nil)
  }

  @Test func changingStockInvalidatesReservationPreview() throws {
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let controller = ConsolidationController()
    try controller.start(container: container)
    let id = try #require(controller.workspace.selectedProjectID)
    controller.updateESIStock([34: 10])
    controller.propose(["Reserve"]) {
      try $0.reserve(projectID: id, quantities: [34: 5], esi: [34: 10], expires: nil)
    }
    controller.updateESIStock([34: 2])
    controller.confirm(catalogBuild: nil)
    #expect(controller.workspace.reservations.isEmpty)
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
